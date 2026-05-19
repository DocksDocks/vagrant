# 0004 — Periodic clipboard-bridge healthcheck timer

**Status:** Accepted
**Branch:** `main`
**Scope:** `scripts/50-vboxclient-supervisor.sh`, `assets/vbox-clipboard-healthcheck.sh`, `assets/systemd/vbox-clipboard-healthcheck.{service,timer}`

## Problem

`VBoxClient --clipboard` keeps a long-lived process alive (`Restart=always`
never fires) but its HGCM↔X11 bridge silently degrades after hours of
uptime. Symptom in the guest: `xclip -selection clipboard -o` returns
`Error: target STRING not available`, `xprop _NET_SELECTION_OWNER_CLIPBOARD`
reports "no such atom", and `journalctl --user -u vbox-clipboard.service`
fills with `Converting VBox formats 'NONE' to '<target>' for X11 ... rc=VERR_NOT_SUPPORTED`.
Observed on this box after ~11 h uptime with the helper still showing
`Active: active (running)` and `NRestarts=0`.

The three-layer fix from plans/0001 does not catch this:
- `Restart=always` needs the process to exit. It doesn't.
- `vbox-clipboard-unlock-watchdog.service` needs a D-Bus
  `org.freedesktop.ScreenSaver.ActiveChanged` signal. On this box
  `light-locker.desktop` is shadowed (`Hidden=true`,
  `scripts/40-xfce-base.sh`) and `xfce4-power-manager` lock is off, so the
  signal is never emitted.

## Root cause

Upstream Oracle bug — same root as plans/0001 but a distinct failure mode:
the process survives, only the bridge dies.

- VBox ticket [#5266 "Shared Clipboard stops working"](https://www.virtualbox.org/ticket/5266) — open since 2009.
- VBox ticket [#19234 "VBoxClient --clipboard terminates silently"](https://www.virtualbox.org/ticket/19234).
- Debian bug [#946843](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=946843) — same symptom on the Debian package.

The `'NONE'` format line appears whenever a guest X11 client requests
clipboard content but the host side hands back an empty format list —
i.e., the bridge is up but no longer carrying data. `systemctl --user
restart vbox-clipboard.service vbox-draganddrop.service` re-establishes
it; one round-trip with `xclip` then succeeds immediately.

## Decision

Add a `systemd --user` timer (`vbox-clipboard-healthcheck.timer`,
`OnBootSec=2min`, `OnUnitActiveSec=2min`) that fires a oneshot service
which runs `~/.local/bin/vbox-clipboard-healthcheck`. The script scans
the clipboard unit's own journal **since its `ActiveEnterTimestamp`** for
the `VBox formats 'NONE'` signature; on hit, it restarts both
`vbox-clipboard.service` and `vbox-draganddrop.service`. After a restart
the journal-since-ActiveEnter window is empty, so the next tick is a
no-op — no restart loop possible.

### CPU cost

One `journalctl` + one `grep` per 2 minutes when the bridge is healthy.
Both terminate in milliseconds. The script does no work on no-symptom
ticks (early-exit on `grep -q` miss). On a hit the cost is one
`systemctl restart` (~200 ms).

### Recovery latency

Up to 2 minutes from the first guest paste-attempt that exposes the
broken bridge. Lowering the interval is cheap (`journalctl` per minute
is still nothing), but 2 min keeps the timer comfortably below the
`AccuracySec=15s` slack budget and the typical "I tried to paste, it
didn't work, let me re-copy" human reaction time.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Prophylactic restart on a 1 h timer regardless of state | Clobbers active X11 selection ownership every hour — anyone holding the clipboard loses it. Healthcheck-then-restart only restarts when broken. |
| Tail `journalctl -f` from a long-running service | More code, more failure modes, no shared journal cursor — would either restart on stale lines from the previous unit lifetime or need its own state file. The timer's `--since=ActiveEnterTimestamp` filter gets the same idempotency for free. |
| Probe by writing+reading with `xclip` | Clobbers the user's current clipboard contents on every tick. Cannot distinguish "bridge broken" from "host clipboard genuinely empty". |
| Re-enable screen lock so the existing unlock watchdog fires | Lock/unlock itself is a documented #5266 trigger (see `CLAUDE.md` and `plans/0001`). Disabling lock is the upstream-recommended workaround; re-enabling it to drive recovery would introduce more failures than it catches. |
| Wait for Oracle to fix upstream | Same `#5266` filed 2009, still open. Not a plan. |

## How it's enabled at provision time

1. `scripts/50-vboxclient-supervisor.sh` adds
   `~/.config/systemd/user/timers.target.wants/` to its `mkdir -p` list.
2. Three new `fetch_asset` calls deploy:
   - `assets/vbox-clipboard-healthcheck.sh` → `~/.local/bin/vbox-clipboard-healthcheck` (chmod 0755).
   - `assets/systemd/vbox-clipboard-healthcheck.service` → `~/.config/systemd/user/vbox-clipboard-healthcheck.service`.
   - `assets/systemd/vbox-clipboard-healthcheck.timer` → `~/.config/systemd/user/vbox-clipboard-healthcheck.timer`.
3. A fourth `ln -sf` line creates
   `~/.config/systemd/user/timers.target.wants/vbox-clipboard-healthcheck.timer`,
   following the same `WantedBy=` symlink trick used for the three
   existing service units (see plans/0001 — `systemctl --user enable`
   cannot run during root provisioning).
4. `scripts/55-permissions.sh` sweeps ownership to `vagrant:vagrant`
   (no new code needed; existing chown-sweep covers the new files).
5. On first login `pam_systemd` starts the user manager, which honours
   the symlink and activates the timer. `OnBootSec=2min` fires the first
   probe two minutes after activation.

## Verification

1. `vagrant provision --provision-with 50-vboxclient-supervisor`
   (idempotent — re-fetches assets, re-creates the symlink).
2. After login:
   ```
   systemctl --user list-timers vbox-clipboard-healthcheck.timer --no-pager
   ```
   Timer must show `LEFT` ≤ 2 min and `UNIT vbox-clipboard-healthcheck.timer`.
3. Dry-run probe with a healthy bridge:
   ```
   /home/vagrant/.local/bin/vbox-clipboard-healthcheck && echo OK
   pgrep -f 'VBoxClient --clipboard'
   ```
   `OK`. PID unchanged before vs after — no restart on clean state.
4. Reproduce the bug (or wait for it). Confirm `xclip -selection clipboard -o`
   fails. Within 2 minutes the timer fires, `journalctl --user -u
   vbox-clipboard.service --since "5 min ago"` shows a new "Service
   started" banner, and `xclip` round-trip succeeds.
5. Idempotency: run the probe twice in a row immediately after a
   restart. Second run exits 0 with no new restart (verified by
   `systemctl --user show -p NRestarts vbox-clipboard.service`
   unchanged).

## Files changed

- `assets/vbox-clipboard-healthcheck.sh` — new (~25 lines).
- `assets/systemd/vbox-clipboard-healthcheck.service` — new (oneshot wrapper).
- `assets/systemd/vbox-clipboard-healthcheck.timer` — new (2-min cadence).
- `scripts/50-vboxclient-supervisor.sh` — adds `mkdir -p ...timers.target.wants`, three `fetch_asset` calls, one `ln -sf` symlink.
- `plans/0004-clipboard-healthcheck-timer.md` — this file.
- `AGENTS.md` — Common Issues bullet updated to mention the new timer.
- `.agents/skills/virtualbox-vmsvga-gotchas/SKILL.md` — `metadata.source_files` + `metadata.updated` bumped.
- `.agents/skills/virtualbox-vmsvga-gotchas/references/clipboard-supervisor-architecture.md` — Layer 5 appended.

No new packages.
