# 0012 — Proactive clipboard-bridge recovery: active read-probe + real-time watcher

**Status:** Accepted
**Branch:** `main`
**Scope:** `scripts/50-vboxclient-supervisor.sh`, `assets/vbox-clipboard-healthcheck.sh`, `assets/vbox-clipboard-bridge-watcher.sh`, `assets/systemd/vbox-clipboard-bridge-watcher.service`

## Problem

The plans/0004 healthcheck timer recovers the silently-dead HGCM↔X11 bridge
(Oracle VBox #5266 / #19234), but only **reactively**: it scans
`vbox-clipboard.service`'s journal for the degraded-bridge signature, and that
signature is only emitted when some app actually attempts a clipboard
*conversion* — i.e. after a paste has already failed. Two consequences:

1. The user always eats at least one failed paste before recovery kicks in.
2. Recovery latency is up to 2 minutes (the timer cadence).

Real incident, 2026-06-23 ~18:27 on this box: the bridge had degraded, but a
guest-side `xclip -selection clipboard -o` still returned **stale** content
(the last thing copied), so no conversion was attempted and no signature was
logged. The 0004 timer had nothing to act on — it had even fired correctly
once at 18:02:31 for an earlier degradation (`Converting VBox formats 'BITMAP'
to 'INVALID' for X11 (fmtX11=0)`), but the later silent state slipped past it.
A manual `systemctl --user restart vbox-clipboard.service vbox-draganddrop.service`
was required.

## Root cause

Not a new failure mode — the same Oracle bug as plans/0001 and plans/0004.
This is a **detection gap**: the existing recovery is log-driven, and the log
is a lagging, paste-triggered indicator.

References (same upstream bug): VBox [#5266](https://www.virtualbox.org/ticket/5266)
(open since 2009), [#19234](https://www.virtualbox.org/ticket/19234),
Debian [#946843](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=946843).

## Decision

Add two complementary detectors on top of the 0004 timer (the timer is kept as
the stateless backstop):

### 1. Active read-probe (Detector 1 inside `vbox-clipboard-healthcheck.sh`)

Every timer tick (2 min), before the journal-scan, probe the live clipboard
**non-destructively**:

```sh
targets=$(timeout 5 xclip -selection clipboard -o -t TARGETS 2>/dev/null || true)
case "$targets" in
  *UTF8_STRING*|*STRING*)
    if ! timeout 5 xclip -selection clipboard -o -t UTF8_STRING >/dev/null 2>&1 \
       && ! timeout 5 xclip -selection clipboard -o -t STRING  >/dev/null 2>&1; then
      restart_bridge   # owner advertises text but delivery fails -> bridge dead
    fi ;;
  # empty / non-text owner: ambiguous -> fall through, never restart on this
esac
```

This catches the failure **proactively** — without waiting for a user paste to
log the signature. It is **read-only** (`xclip -o`), so it never takes
selection ownership and cannot clobber the user's clipboard (the reason
plans/0004 rejected a write+read probe). It restarts only on the unambiguous
"owner present, delivery broken" state; an empty or image-only clipboard is
left alone (no false-positive restart).

### 2. Real-time bridge watcher (Layer 6, `vbox-clipboard-bridge-watcher.service`)

A long-running supervised `systemd --user` service tails the clipboard unit's
journal and restarts within ~1 s of the degraded-bridge signature, instead of
waiting up to 2 min for the timer:

```sh
exec journalctl --user -u vbox-clipboard.service -f -n0 -o cat |
while read -r line; do
  case "$line" in
    *"VBox formats 'NONE'"*|*"to 'INVALID' for X11"*)
      now=$(date +%s)
      if [ $(( now - ${last:-0} )) -ge 10 ]; then
        last=$now
        systemctl --user restart vbox-clipboard.service vbox-draganddrop.service
      fi ;;
  esac
done
```

Structurally identical to the existing `vbox-clipboard-unlock-watchdog.service`
(a long-running `dbus-monitor | while read` under `Restart=always`).

#### Why `journalctl -f` now, when plans/0004 rejected it

0004 rejected a follow-tail for two reasons; both are defeated here:

- *"restart on stale lines from the previous unit lifetime / need a state
  file"* → `-n0` starts at the journal **tail** (zero history), so only lines
  emitted after the watcher starts are ever seen. No cursor file needed.
- *"more failure modes"* → `Restart=always` re-establishes the follow if it
  dies, and a **10 s debounce** prevents a burst of error lines (or lines
  emitted in the window before a restart takes effect) from triggering a
  restart storm. The follow tracks the unit *by name*, so it survives the
  restarts it triggers; restart banners ("Service started", "Initializing X11")
  don't match the signature, so there is no self-trigger loop.

### Known limitation (honest scope)

A **pure host→guest stale-content stall** — where the guest's own
`xclip -o` still succeeds returning old content while a freshly-copied host
clipboard never arrives — cannot be detected from inside the guest by *any*
method. The guest cannot see the host clipboard to compare against, and this
setup has no host-side daemon to ask (the Vagrantfile runs host-side only at
`up`/`provision`, not as a service). The read-probe + watcher cover the
realistic "bridge dead in both directions" failures; this corner case still
requires a manual re-copy or the user noticing staleness.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Keep log-scan only, lower the timer to ~30 s | Still reactive — needs a failed paste to log first; doesn't catch the 2026-06-23 silent case at any cadence. |
| Write+read (sentinel) probe | Takes CLIPBOARD selection ownership every tick — clobbers the user's content; rich content (images/files) degraded to nothing; races an in-progress copy. Also mostly tests *local* X11 (the writing process serves its own read-back), not the HGCM↔X11 bridge that actually fails. plans/0004 rejected this. |
| Replace the timer with the real-time watcher | The timer carries the proactive read-probe (no log needed) and is a stateless backstop if the watcher dies; they cover different gaps, so keep both. |
| Prophylactic periodic restart | Clobbers active selection ownership on every cycle (plans/0004). |
| Host-side agent to verify host→guest delivery | No persistent host process in this Vagrant setup; large scope for the one corner case that remains. |
| Wait for Oracle to fix #5266 | Open since 2009. |

## How it's enabled at provision time

1. `scripts/50-vboxclient-supervisor.sh` gains two `fetch_asset` calls
   (`vbox-clipboard-bridge-watcher.sh` → `~/.local/bin/` chmod 0755;
   `systemd/vbox-clipboard-bridge-watcher.service` → `~/.config/systemd/user/`)
   and one `ln -sf` into `default.target.wants/` — the same WantedBy-symlink
   trick used for the other units (plans/0001; `systemctl --user enable` can't
   run during root provisioning).
2. `assets/vbox-clipboard-healthcheck.sh` gains Detector 1 (the read-probe)
   ahead of the existing journal-scan; the timer/service that drive it are
   unchanged.
3. `scripts/55-permissions.sh` sweeps ownership to `vagrant:vagrant` (existing
   chown-sweep covers the new files; no new code).
4. On first login `pam_systemd` starts the user manager, which honours the
   new symlink and starts the watcher; `vboxclient-session.desktop` already
   imports `DISPLAY`/`XAUTHORITY` into the manager so the timer's read-probe
   has an X connection.

## Verification

Performed live on this box (`dev-box`, GA 7.2.4) on 2026-06-23 after deploying
the assets directly (no full re-provision needed):

1. `shellcheck` clean on `vbox-clipboard-bridge-watcher.sh`,
   `vbox-clipboard-healthcheck.sh`, and `scripts/50-vboxclient-supervisor.sh`.
2. Watcher running with its follow alive:
   ```
   systemctl --user status vbox-clipboard-bridge-watcher.service
   # Active: active (running); CGroup includes
   #   journalctl --user -u vbox-clipboard.service -f -n0 -o cat
   ```
3. Signature match (dry-run): both `'NONE'` and `to 'INVALID' for X11` lines
   matched; `Service started` / `Initializing X11 clipboard` ignored.
4. `systemctl --user show-environment` reports `DISPLAY=:0.0` and
   `XAUTHORITY=/home/vagrant/.Xauthority` — so the timer-run read-probe runs
   rather than self-skipping.
5. Read-probe truth table (stubbed `xclip`): `degraded → RESTART`;
   `healthy / empty / image-only → no-op`. Running the real
   `vbox-clipboard-healthcheck` against the live healthy clipboard left
   `NRestarts` unchanged (0 → 0) — no false-positive restart.

## Files changed

- `assets/vbox-clipboard-bridge-watcher.sh` — new (real-time follow + debounce).
- `assets/systemd/vbox-clipboard-bridge-watcher.service` — new (`Restart=always`, mirrors the unlock-watchdog unit).
- `assets/vbox-clipboard-healthcheck.sh` — add Detector 1 (non-destructive read-probe) ahead of the journal-scan.
- `scripts/50-vboxclient-supervisor.sh` — two `fetch_asset` calls + one `ln -sf` symlink for the watcher.
- `plans/0012-clipboard-readprobe-realtime-watcher.md` — this file.
- `AGENTS.md` — Common Issues bullet updated (read-probe + real-time watcher).
- `.agents/skills/virtualbox-vmsvga-gotchas/SKILL.md` — `source_files` + `updated` bumped, description extended.
- `.agents/skills/virtualbox-vmsvga-gotchas/references/clipboard-supervisor-architecture.md` — Layer 6 added, Layer 5 read-probe noted.

No new packages (`xclip` already installed; see AGENTS.md Installed Tools).
