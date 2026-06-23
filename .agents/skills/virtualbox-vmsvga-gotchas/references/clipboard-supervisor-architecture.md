# Clipboard Supervisor Architecture

<constraint>
The three-layer fix is required as a unit. Removing any layer re-exposes the underlying Oracle VBox #5266/#19234 bug. Keep all three: systemd units + WantedBy symlinks + XDG autostart.
</constraint>

## Root Cause

`VBoxClient --clipboard` terminates silently on rapid RandR reconfiguration, VT switches, and long uptime. This is Oracle VirtualBox bug #5266 (filed 2009, unfixed). `--draganddrop` has the same failure mode.

The xev-based autoresize workaround (`vbox-autoresize.desktop`) fires `xrandr --output Virtual-1 --preferred` on every `ScreenChangeNotify`, making rapid X reconfiguration a frequent trigger. This makes clipboard failure a common occurrence in this specific setup.

References: VBox [#5266](https://www.virtualbox.org/ticket/5266), [#6150](https://www.virtualbox.org/ticket/6150), [#19234](https://www.virtualbox.org/ticket/19234), NixOS [nixpkgs#65542](https://github.com/NixOS/nixpkgs/issues/65542).

## Layer 1: systemd --user Service Units

```ini
[Service]
Type=simple
ExecStart=/usr/bin/VBoxClient --clipboard --nodaemon
Restart=always
RestartSec=2s
StartLimitIntervalSec=0
```

Source: `assets/systemd/vbox-clipboard.service:6-11`

`StartLimitIntervalSec=0` disables systemd's default burst-restart rate limit (5 restarts in 10s = stopped). Without it, repeated silent exits exhaust the burst allowance and systemd stops trying to restart the unit.

CPU cost: `VBoxClient --clipboard --nodaemon` blocks on an HGCM ioctl — the kernel parks the process. Not a polling loop. Steady-state: one extra pid + ~few KB RSS. Source: `plans/0001-clipboard-supervisor.md:45-49`.

**Three units deployed:**
- `assets/systemd/vbox-clipboard.service` → `~/.config/systemd/user/vbox-clipboard.service`
- `assets/systemd/vbox-draganddrop.service` → `~/.config/systemd/user/vbox-draganddrop.service`
- `assets/systemd/vbox-clipboard-unlock-watchdog.service` → `~/.config/systemd/user/vbox-clipboard-unlock-watchdog.service`

Source: `scripts/50-vboxclient-supervisor.sh:22-32`

## Layer 2: WantedBy Symlinks (replaces `systemctl --user enable`)

```bash
ln -sf ../vbox-clipboard.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard.service
ln -sf ../vbox-draganddrop.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-draganddrop.service
ln -sf ../vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard-unlock-watchdog.service
```

Source: `scripts/50-vboxclient-supervisor.sh:34-41`

`systemctl --user enable` requires `XDG_RUNTIME_DIR` and an active `pam_systemd` session, neither of which exist during root provisioning. Direct symlink creation is what the command does internally and is safe to execute as root.

On first login, `pam_systemd` starts the user manager which reads `default.target.wants/` and activates the units. The units start WITHOUT `DISPLAY`/`XAUTHORITY` at this point — that's handled by Layer 3.

## Layer 3: XDG Autostart — Import Session Environment

```ini
Exec=sh -c "sleep 3 && systemctl --user import-environment DISPLAY XAUTHORITY && systemctl --user restart vbox-clipboard.service vbox-draganddrop.service && VBoxClient --vmsvga 2>/dev/null; VBoxClient --seamless 2>/dev/null; VBoxClient --display 2>/dev/null; true"
```

Source: `assets/vboxclient-session.desktop:4`

The user manager env doesn't inherit `DISPLAY`/`XAUTHORITY` from the X session. `import-environment` propagates them from the current shell into the manager, then `restart` kicks the units so they pick up the new env.

The `sleep 3` gives the X session time to fully initialize before `import-environment` runs.

One-shot helpers (`--vmsvga`, `--seamless`, `--display`) don't need supervision — they run once at startup and exit cleanly.

## Layer 4 (Belt-and-Braces): D-Bus ScreenSaver Watchdog

```bash
exec dbus-monitor --session \
  "interface=org.freedesktop.ScreenSaver,member=ActiveChanged" 2>/dev/null |
while read -r line; do
  case "$line" in
    *"boolean false"*)
      sleep 1
      systemctl --user try-restart \
        vbox-clipboard.service vbox-draganddrop.service 2>/dev/null || true
      ;;
  esac
done
```

Source: `assets/vbox-clipboard-unlock-watchdog.sh:16-27`

On screen-unlock, the X session re-grabs display resources and the restarted clipboard helper (from `Restart=always`) can lose the race. Kicking it again 1s after `ActiveChanged=false` clears that window. Only activates if screen locking is re-enabled by the user — screen lock is disabled by default.

## Layer 5 (Belt-and-Braces): Periodic Healthcheck Timer

```bash
since=$(systemctl --user show -p ActiveEnterTimestamp --value vbox-clipboard.service)
if journalctl --user -u vbox-clipboard.service --since "$since" --no-pager \
   | grep -qE "VBox formats 'NONE'|to 'INVALID' for X11"; then
  systemctl --user restart vbox-clipboard.service vbox-draganddrop.service
fi
```

Source: `assets/vbox-clipboard-healthcheck.sh:14-23`, fired by `vbox-clipboard-healthcheck.timer` (`OnBootSec=2min`, `OnUnitActiveSec=2min`).

Catches a **distinct failure mode** from Layers 1-4: the helper process stays alive (so `Restart=always` never fires) but its HGCM↔X11 bridge silently dies. Two sister signatures, both `VERR_NOT_SUPPORTED`: `Converting VBox formats 'NONE' to <X>` (source-side empty) or `Converting VBox formats <X> to 'INVALID'` with `fmtX11=0` (X11-side has no valid target). Either appears whenever a guest app requests clipboard content over the dead bridge. Layer 4's D-Bus watchdog needs a screen-unlock event, and on this box `light-locker.desktop` is shadowed (`Hidden=true`, `scripts/40-xfce-base.sh`) so that signal never arrives.

The `--since=ActiveEnterTimestamp` filter is what keeps the timer idempotent: after a restart the journal-since-ActiveEnter window is empty, so subsequent ticks early-exit at the `grep -q` with no restart. No state file, no cursor file. Source: `plans/0004-clipboard-healthcheck-timer.md`.

**Detector 1 — active read-probe (added plans/0012):** ahead of the journal-scan, the same script probes the live clipboard non-destructively. If `xclip -selection clipboard -o -t TARGETS` advertises a text target (`UTF8_STRING`/`STRING`) but neither target can actually be read, the owner is present but delivery is broken → restart. This catches the bug **proactively** — the journal-scan only sees it *after* a real paste logs a conversion error. It is read-only (`xclip -o`), so it never takes selection ownership and cannot clobber the user's clipboard (the reason a write+read probe was rejected in plans/0004). An empty or image-only clipboard is ambiguous (broken vs genuinely empty) and is left alone — no false-positive restart. Needs `DISPLAY`/`XAUTHORITY`, imported into the user manager at login by `vboxclient-session.desktop`. Source: `assets/vbox-clipboard-healthcheck.sh`.

Why a timer rather than a `journalctl -f` tail for *this* unit: oneshot + `--since` is stateless and survives systemd restarts cleanly. The real-time follow-tail concern is handled separately by Layer 6 (which defeats the stale-line problem with `-n0`).

## Layer 6 (Real-time): Bridge Watcher

```bash
exec journalctl --user -u vbox-clipboard.service -f -n0 -o cat |
while read -r line; do case "$line" in
  *"VBox formats 'NONE'"*|*"to 'INVALID' for X11"*)  # 10s-debounced restart
    systemctl --user restart vbox-clipboard.service vbox-draganddrop.service ;;
esac; done
```

Source: `assets/vbox-clipboard-bridge-watcher.sh`, run by `vbox-clipboard-bridge-watcher.service` (`Restart=always`, mirrors the unlock-watchdog unit).

Cuts recovery latency on a *logged* failure from ≤2 min (Layer 5's cadence) to ~1 s. plans/0004 rejected a `journalctl -f` tail over stale-line replay and cursor-file state; `-n0` defeats both — it starts at the journal **tail**, so only lines emitted after the watcher starts are seen, no cursor file required. `Restart=always` re-establishes the follow if it dies; the 10 s debounce stops a burst of error lines (or lines emitted in the window before a restart lands) from causing a restart storm. The follow tracks the unit *by name*, so it survives the restarts it triggers; restart banners don't match the signature, so there is no self-trigger loop. Source: `plans/0012-clipboard-readprobe-realtime-watcher.md`.

**Layer 5 vs Layer 6 division of labour:** Layer 6 is the fast path for *logged* (paste-triggered) failures; Layer 5's read-probe is the proactive path that needs no paste, and its journal-scan is the stateless backstop if the watcher is down. **Limitation (both layers):** a pure host→guest *stale-content* stall — guest `xclip -o` still returns old content while a fresh host copy never arrives — is undetectable from inside the guest (no host clipboard to compare, no host-side daemon).

## Verification Steps

```bash
# After login
systemctl --user status vbox-clipboard.service vbox-draganddrop.service
pgrep -af VBoxClient

# Prove self-healing
pkill -fx "/usr/bin/VBoxClient --clipboard --nodaemon"
sleep 3
systemctl --user status vbox-clipboard.service  # restart count increments

# Check logs
journalctl --user -u vbox-clipboard -n 50 --no-pager
```

Source: `plans/0001-clipboard-supervisor.md:72-90`

## Gotchas

**Removing `light-locker.desktop` override**: if screen lock re-enables, `VBoxClient --clipboard` terminates during lock/unlock X-event storms. `Restart=always` recovers it, but the D-Bus watchdog is required as belt-and-braces. Source: `scripts/40-xfce-base.sh:51-62`.

**WantedBy symlink target is `../vbox-clipboard.service`** (relative path): the symlink is in `default.target.wants/` so `..` points to the `user/` directory where the service files live. Using an absolute path here breaks portability.

**`import-environment` timing**: if the XDG autostart runs before the X session fully initializes, `DISPLAY` may not be set yet. The `sleep 3` guard handles this in practice; on very slow VMs it may need to be increased.
