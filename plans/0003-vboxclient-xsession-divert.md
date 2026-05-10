# 0003 — Disable Oracle's Xsession.d VBoxClient launcher (gap from plan 0001)

**Status:** Accepted
**Branch:** `main`
**Scope:** `scripts/50-vboxclient-supervisor.sh`, `.claude/skills/virtualbox-vmsvga-gotchas/SKILL.md`

## Problem

Plan 0001 replaced the `VBoxClient-all` autostart with two supervised
`systemd --user` units (`vbox-clipboard.service`, `vbox-draganddrop.service`).
On a freshly-provisioned VM the supervised units appeared to work, but in
practice they never owned the clipboard helper. Symptoms surfaced after a
`vagrant suspend` / VM `Save State` round-trip: copy/paste stopped working
between host and guest, and `systemctl --user status vbox-clipboard.service`
showed `Restart=always` cycling endlessly with:

```
VBoxClient[…]: Shared Clipboard: service already running, exitting
vbox-clipboard.service: Scheduled restart job, restart counter is at 38.
```

A separate, long-lived `VBoxClient --clipboard` process (started outside
systemd, no `--nodaemon`) was holding the X11 root atom
`VBOXCLIENT_STARTED=1`. Each restart attempt by the supervised unit found
the atom set, exited cleanly, and tripped the next restart 2 s later.

## Root cause

Plan 0001 removed the obsolete user-side autostart but did not touch
Oracle's session-wide launcher at
`/etc/X11/Xsession.d/98vboxadd-xclient` (shipped by
`virtualbox-guest-utils` / `virtualbox-guest-x11`). That script runs at
every X login and starts:

```sh
/usr/bin/VBoxClient --clipboard
/usr/bin/VBoxClient --seamless
/usr/bin/VBoxClient --draganddrop
/usr/bin/VBoxClient --checkhostversion
/usr/bin/VBoxClient --vmsvga-session
```

The `--clipboard` and `--draganddrop` processes win the X11 atom race
before the user systemd manager fully comes up, so the supervised units
can never become the owner.

After `vagrant suspend` → resume, the original Xsession.d-spawned
`VBoxClient --clipboard` stays alive but its host-clipboard channel is
broken. Nothing recovers it: the supervised unit can't replace it
(atom collision), the unlock watchdog only fires on screen-unlock, and
no signal in the guest corresponds to a VM resume event.

The underlying silent-exit Oracle bug is the same one plan 0001
addresses with `Restart=always`:

- Oracle VBox [#5266 "Shared Clipboard stops working"](https://www.virtualbox.org/ticket/5266) — silent exit on X-event storms.
- Oracle VBox [#6150](https://www.virtualbox.org/ticket/6150) — duplicate of #5266.
- Oracle VBox [#19234](https://www.virtualbox.org/ticket/19234) — silent exit on lock/unlock.
- NixOS [nixpkgs#65542 "VBoxClient --clipboard terminates silently"](https://github.com/NixOS/nixpkgs/issues/65542) — independent confirmation of the bug.

Plan 0001's recovery layer never gets a chance to act because the
Xsession.d-spawned helper holds the X11 atom and the supervised unit
exits immediately with `Shared Clipboard: service already running, exitting`
before its restart counter can do useful work. Disabling the
Xsession.d entry is the prerequisite that lets plan 0001's
`Restart=always` actually recover after VM resume.

`/etc/X11/Xsession.d/` files are sourced by `Xsession` via
`run-parts`. Debian's `Xsession(5)` man page explicitly recommends
renaming a file with a suffix (`.old`, `.broken`, `.disabled`) as the
official way to skip an entry without deleting it — the same effect
`dpkg-divert --rename` produces, with the bonus that the rename
survives `apt upgrade virtualbox-guest-utils`.

## Decision

`dpkg-divert` `/etc/X11/Xsession.d/98vboxadd-xclient` to a
`.disabled` sibling at provision time. The autostart entry
`vboxclient-session.desktop` already handles `--vmsvga`, `--seamless`,
`--display`, and triggers the supervised `--clipboard` / `--draganddrop`
units, so Oracle's Xsession.d script is fully redundant after plan 0001.

`dpkg-divert` is the standard Debian mechanism for overriding a
package-provided file: the rename survives `apt upgrade
virtualbox-guest-utils`, and `dpkg-divert --remove` cleanly reverts it.

## Alternatives considered

| Option | Why rejected |
|---|---|
| `sed -i` to comment out only the `--clipboard` and `--draganddrop` lines | Loses the override on every package upgrade. Also fragile if Oracle re-flows the script. |
| `chmod -x /etc/X11/Xsession.d/98vboxadd-xclient` | `Xsession.d` reads files via `.` (source), not `exec` — `chmod -x` doesn't actually skip them. And `dpkg` resets perms on upgrade. |
| `rm -f /etc/X11/Xsession.d/98vboxadd-xclient` | Restored on next `apt upgrade`. |
| Add `ExecStartPre` to supervised units that `pkill` Oracle's helper + clear the X11 atom | Works, but only after the supervised unit actually starts — there's still a window where Oracle's helper owns the channel. dpkg-divert removes the conflict at the source. |

## How it's enabled at provision time

The new block in `scripts/50-vboxclient-supervisor.sh` runs as root and
is idempotent:

```sh
if [ -f /etc/X11/Xsession.d/98vboxadd-xclient ] && \
   ! dpkg-divert --list /etc/X11/Xsession.d/98vboxadd-xclient 2>/dev/null \
       | grep -q '98vboxadd-xclient\.disabled'; then
  dpkg-divert --add --rename --quiet \
    --divert /etc/X11/Xsession.d/98vboxadd-xclient.disabled \
    /etc/X11/Xsession.d/98vboxadd-xclient
fi
```

The `dpkg-divert --list` check is the idempotency gate so re-running
`vagrant provision` is a no-op once the divert is in place.

## Verification

1. On a new `vagrant up`:
   ```
   ls -la /etc/X11/Xsession.d/
   ```
   `98vboxadd-xclient.disabled` exists; `98vboxadd-xclient` does not.
   `dpkg-divert --list /etc/X11/Xsession.d/98vboxadd-xclient` shows the
   divert is registered.

2. After login:
   ```
   pgrep -af VBoxClient
   ```
   Exactly one `VBoxClient --clipboard --nodaemon` (under
   `vbox-clipboard.service`) and one `VBoxClient --draganddrop --nodaemon`
   (under `vbox-draganddrop.service`). No stray Oracle-spawned helpers.

3. `systemctl --user status vbox-clipboard.service vbox-draganddrop.service`
   — both `active (running)`, restart counter stable.

4. Save-state round-trip: `vagrant suspend && vagrant resume` (or
   VirtualBox UI Save State → Start). Clipboard works immediately, or
   recovers within `RestartSec=2s` if the helper exited on resume.

## Live VM recovery

For a VM provisioned before this change, apply the divert by hand and
clear the bad state:

```sh
sudo dpkg-divert --add --rename \
  --divert /etc/X11/Xsession.d/98vboxadd-xclient.disabled \
  /etc/X11/Xsession.d/98vboxadd-xclient

systemctl --user stop vbox-clipboard.service vbox-draganddrop.service
pkill -f 'VBoxClient.*--clipboard' || true
pkill -f 'VBoxClient.*--draganddrop' || true
DISPLAY=:0 xprop -root -remove VBOXCLIENT_STARTED 2>/dev/null || true
rm -f "$HOME"/.vboxclient-clipboard-*.pid "$HOME"/.vboxclient-draganddrop-*.pid

systemctl --user reset-failed vbox-clipboard.service vbox-draganddrop.service
systemctl --user start vbox-clipboard.service vbox-draganddrop.service
```

`pgrep -af VBoxClient` should then show one `--clipboard --nodaemon`
and one `--draganddrop --nodaemon` process.

## Files changed

- `scripts/50-vboxclient-supervisor.sh` — added the `dpkg-divert` block.
- `plans/0003-vboxclient-xsession-divert.md` — this plan.

No new assets, no `.desktop` / unit-file changes.
