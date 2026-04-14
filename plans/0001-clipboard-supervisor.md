# 0001 — Supervise VBoxClient clipboard & drag-and-drop via `systemd --user`

**Status:** Accepted
**Branch:** `claude/fix-vagrant-clipboard-1PIui`
**Scope:** `Vagrantfile` only

## Problem

Inside the provisioned Debian 13 guest, the VirtualBox shared clipboard
works after first login but silently stops working some time later — often
(but not always) correlating with a window resize. Re-logging in or
rebooting the VM restores it until the next spontaneous break.

## Root cause

`VBoxClient --clipboard` is a per-feature userland helper spawned once by
`VBoxClient-all` at login. It terminates silently on certain X-server
events (rapid RandR reconfiguration, VT switches, long uptime). Nothing
restarts it, so once the process is gone, clipboard integration is dead
until the next login.

This is an upstream Oracle bug with a 15-year tail:

- VBox ticket [#5266 "Shared Clipboard stops working"](https://www.virtualbox.org/ticket/5266) — never fully fixed.
- VBox ticket [#6150](https://www.virtualbox.org/ticket/6150) — duplicate of #5266.
- NixOS [nixpkgs#65542 "VBoxClient --clipboard terminates silently"](https://github.com/NixOS/nixpkgs/issues/65542).
- Community forum threads: [t=48923](https://forums.virtualbox.org/viewtopic.php?f=6&t=48923), [t=99192](https://forums.virtualbox.org/viewtopic.php?t=99192).

Why "after a resize" fits: this repo's `vbox-autoresize.desktop` autostart
(the `xev`/`xrandr` workaround for kernel-6.19 GA breakage) fires
`xrandr --output Virtual-1 --preferred` on every `ScreenChangeNotify`.
Rapid X reconfiguration is a known trigger for the helper's silent exit.

`--draganddrop` has the same failure mode.

## Decision

Replace the single-shot `VBoxClient-all` autostart with two supervised
`systemd --user` units (`vbox-clipboard.service`, `vbox-draganddrop.service`)
with `Restart=always` and `RestartSec=2s`. A small XDG autostart entry
bootstraps the session by importing `DISPLAY`/`XAUTHORITY` into the user
manager and (re)starting the two units; it also launches the one-shot
helpers (`--vmsvga`, `--seamless`, `--display`) that don't need supervision.

### CPU cost

Effectively zero. `VBoxClient --clipboard --nodaemon` blocks on an HGCM
ioctl — it is not a polling loop, the kernel parks the process. `systemd
--user` only wakes when a child exits, which is rare. Steady-state cost
is one extra pid per helper plus a few kilobytes of RSS.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Shell `while` supervisor in an autostart `.desktop` | Works, but no journaled logs, harder to run helpers in parallel, non-standard. Matches the existing `vbox-autoresize.desktop` pattern but worse ergonomics than a real service. |
| Cron/`watch`-style poll that restarts `VBoxClient --clipboard` on schedule | Polling is wasteful; doesn't restart immediately on death; races with a live helper. |
| Kill the autoresize autostart (suspected trigger) | Even if resize-induced, the underlying helper-exit bug has multiple triggers; fixing only one makes the symptom rarer, not gone. Also we need the autoresize workaround for kernel 6.19 (see CLAUDE.md). |
| Wait for Oracle to fix it upstream | Bug filed in 2009, still open. Not a plan. |

## How it's enabled at provision time

`systemctl --user enable` can't run during VM provisioning (no active
user manager, no `XDG_RUNTIME_DIR`). Instead the provisioner creates the
`WantedBy=default.target` symlinks directly under
`~/.config/systemd/user/default.target.wants/`. On first login, `pam_systemd`
starts the user manager, which honours those symlinks and activates the
units. The autostart `.desktop` entry then runs inside the X session and
`systemctl --user restart`s the units so they pick up the correct
`DISPLAY`/`XAUTHORITY`.

## Verification

1. `vagrant provision` (idempotent; old `vboxclient-all.desktop` is removed).
2. After login:
   ```
   systemctl --user status vbox-clipboard.service vbox-draganddrop.service
   pgrep -af VBoxClient
   ```
   Both units `active (running)`; one `--clipboard --nodaemon` and one `--draganddrop --nodaemon` process.
3. Golden path: host → guest and guest → host copy/paste both work.
4. Reproduce the old break: resize the VM window many times, toggle full-screen. Clipboard still works.
5. Prove self-healing:
   ```
   pkill -fx "/usr/bin/VBoxClient --clipboard --nodaemon"
   sleep 3
   systemctl --user status vbox-clipboard.service
   ```
   Unit restart count increments; a new process appears within ~2 s; clipboard works immediately.
6. `journalctl --user -u vbox-clipboard -n 50 --no-pager` shows no crash-loop spam.

## Files changed

- `Vagrantfile` — block around the old `VBoxClient-all` autostart replaced with the systemd-user setup.

No new packages. No other files.
