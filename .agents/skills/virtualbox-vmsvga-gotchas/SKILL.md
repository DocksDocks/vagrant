---
name: virtualbox-vmsvga-gotchas
description: Use when diagnosing or modifying VirtualBox guest graphics, clipboard, drag-and-drop, auto-resize, or Chrome: --graphicscontroller vmsvga (NOT vboxsvga/Windows-only), 256 MB --vram ceiling, vblank_mode=off in assets/xfwm4.xml, no VirtualBox 3D accel (regresses xfwm4 compositing AND Chrome); supervising VBoxClient --clipboard/--draganddrop via systemd --user units (Restart=always) with silently-dead HGCM<->X11 bridge recovery for Oracle #5266/#19234 — vbox-clipboard-unlock-watchdog.service, the 2-min vbox-clipboard-healthcheck.timer (journal-scan for VBox formats 'NONE'/to 'INVALID' + non-destructive xclip read-probe), and the real-time vbox-clipboard-bridge-watcher.service (journalctl -f -n0); the *.wants symlink trick (no systemctl --user enable at provision); the xev/xrandr autoresize workaround (vbox-autoresize.desktop, #568); chrome-policy-no-gpu.json HardwareAccelerationModeEnabled=false (VBox #15417). Not for XFCE theme/dconf config, shell-script conventions, or Vagrantfile host detection.
user-invocable: false
metadata:
  pattern: tool-wrapper
  source_files:
    - "Vagrantfile"
    - "scripts/40-xfce-base.sh"
    - "scripts/50-vboxclient-supervisor.sh"
    - "scripts/51-vbox-autoresize.sh"
    - "scripts/30-guest-additions.sh"
    - "assets/xfwm4.xml"
    - "assets/systemd/vbox-clipboard.service"
    - "assets/systemd/vbox-draganddrop.service"
    - "assets/systemd/vbox-clipboard-unlock-watchdog.service"
    - "assets/systemd/vbox-clipboard-healthcheck.service"
    - "assets/systemd/vbox-clipboard-healthcheck.timer"
    - "assets/systemd/vbox-clipboard-bridge-watcher.service"
    - "assets/vbox-clipboard-unlock-watchdog.sh"
    - "assets/vbox-clipboard-healthcheck.sh"
    - "assets/vbox-clipboard-bridge-watcher.sh"
    - "assets/vboxclient-session.desktop"
    - "assets/vbox-autoresize.desktop"
    - "assets/chrome-policy-no-gpu.json"
    - "plans/0001-clipboard-supervisor.md"
    - "plans/0003-vboxclient-xsession-divert.md"
    - "plans/0004-clipboard-healthcheck-timer.md"
    - "plans/0012-clipboard-readprobe-realtime-watcher.md"
    - "CLAUDE.md"
  updated: "2026-06-23"
---

# VirtualBox VMSVGA Gotchas

<constraint>
NEVER change `--graphicscontroller` from `vmsvga` to `vboxsvga`. VBoxSVGA is Windows-only; Linux guests get a black screen from boot because `vboxvideo` driver is absent. Source: `Vagrantfile:105`.
</constraint>

<constraint>
NEVER enable VirtualBox 3D acceleration. It regresses xfwm4 compositing (black screen after login) AND makes Chrome GPU probing worse on Linux guests. Source: `CLAUDE.md` (Chrome freezes, Black screen after login).
</constraint>

<constraint>
Keep `vblank_mode=off` in `assets/xfwm4.xml` even when compositing is enabled. xfwm4 treats llvmpipe/SVGA3D/virgl (what VMSVGA exposes) as unsupported GL for vblank — removing this causes "Unsupported GL renderer" warnings and unstable compositing paths. Source: `assets/xfwm4.xml:6-7`.
</constraint>

<constraint>
Keep `/etc/opt/chrome/policies/managed/no-gpu.json` deployed. Removing it causes Chrome to deadlock under combined load (Next.js + Chrome + Claude) because VMSVGA has no real GPU (VBox bug #15417). Source: `scripts/40-xfce-base.sh:80-85`.
</constraint>

<constraint>
Keep Oracle's `/etc/X11/Xsession.d/98vboxadd-xclient` disabled via `dpkg-divert` (renamed to `.disabled`). If it runs at X login it pre-launches `VBoxClient --clipboard` / `--draganddrop` outside systemd, those processes claim the X11 `VBOXCLIENT_STARTED` atom, and the supervised units in plans/0001 can never take over (symptom: `vbox-clipboard.service` stuck in Restart=always loop with `Shared Clipboard: service already running, exitting`, save-state→resume cannot auto-recover). Source: `scripts/50-vboxclient-supervisor.sh`, `plans/0003-vboxclient-xsession-divert.md`.
</constraint>

## When to Use

- Diagnosing black screen on boot or after login.
- Clipboard stops working after window resize or after a while.
- Auto-resize (guest window resize) not following host window.
- Chrome freezes under load (Next.js dev server, Claude Code).
- Investigating systemd --user unit failures for VBoxClient.
- Adding a new VBoxClient helper that needs supervision.
- Understanding why `systemctl --user enable` is not used during provisioning.
- Verifying the fix at `chrome://policy` or `chrome://gpu`.

## Core Patterns

### Graphics controller — VMSVGA only

```ruby
vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
vb.customize ["modifyvm", :id, "--vram", "256"]
```

Source: `Vagrantfile:104-105`. 256 MB is the hard ceiling — values above are silently clamped. VMSVGA uses the mainline `vmwgfx` kernel driver (Debian 13 kernel 6.12). VBoxSVGA uses `vboxvideo` which may not load.

### xfwm4 compositor config — compositing ON, vblank OFF

```xml
<property name="use_compositing" type="bool" value="true"/>
<property name="vblank_mode" type="string" value="off"/>
```

Source: `assets/xfwm4.xml:6-7`. Software-rendered compositing (rounded corners, shadows) works fine under VMSVGA without 3D acceleration. Only the vblank path is broken (GL renderer detection in xfwm4 `src/compositor.c`).

### Chrome managed policy — hardware acceleration disabled

```bash
fetch_asset chrome-policy-no-gpu.json /etc/opt/chrome/policies/managed/no-gpu.json
chmod 0644 /etc/opt/chrome/policies/managed/no-gpu.json
```

```json
{
  "HardwareAccelerationModeEnabled": false
}
```

Source: `scripts/40-xfce-base.sh:80-85`, `assets/chrome-policy-no-gpu.json:1-3`. Managed policy survives `apt upgrade google-chrome-stable` and applies to every Chrome launch path. Verify at `chrome://policy` (Machine scope, status OK) and `chrome://gpu` (all rows "Software only" or "Disabled").

### VBoxClient supervisor — three-layer architecture

**Layer 1: systemd --user units with Restart=always**

```ini
[Service]
Type=simple
ExecStart=/usr/bin/VBoxClient --clipboard --nodaemon
Restart=always
RestartSec=2s
StartLimitIntervalSec=0
```

Source: `assets/systemd/vbox-clipboard.service:6-11`. `StartLimitIntervalSec=0` disables burst-restart limits — critical because Oracle bug #5266 causes the helper to terminate arbitrarily.

**Layer 2: WantedBy symlinks instead of `systemctl --user enable`**

```bash
ln -sf ../vbox-clipboard.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard.service
ln -sf ../vbox-draganddrop.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-draganddrop.service
ln -sf ../vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard-unlock-watchdog.service
```

Source: `scripts/50-vboxclient-supervisor.sh:34-41`. `systemctl --user enable` requires an active user manager (`XDG_RUNTIME_DIR`, `pam_systemd`) which doesn't exist during provisioning. Direct symlink creation is what `systemctl --user enable` does internally and is safe to do as root.

**Layer 3: XDG autostart — DISPLAY/XAUTHORITY import + session restart**

```ini
Exec=sh -c "sleep 3 && systemctl --user import-environment DISPLAY XAUTHORITY && systemctl --user restart vbox-clipboard.service vbox-draganddrop.service && VBoxClient --vmsvga 2>/dev/null; VBoxClient --seamless 2>/dev/null; VBoxClient --display 2>/dev/null; true"
```

Source: `assets/vboxclient-session.desktop:4`. systemd --user units started at login lack `DISPLAY`/`XAUTHORITY`; `import-environment` propagates them so the restarted clipboard unit can connect to X.

### D-Bus ScreenSaver watchdog (belt-and-braces on unlock)

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

Source: `assets/vbox-clipboard-unlock-watchdog.sh:16-27`. On screen-unlock the restarted clipboard helper can race the X session re-grab; kicking it again on `ActiveChanged=false` clears that race window.

### xev auto-resize workaround (VBox bug #568)

```ini
Exec=sh -c "sleep 3 && xrandr --output Virtual-1 --preferred 2>/dev/null; xev -root -event randr | while read -r line; do case $line in *ScreenChangeNotify*) sleep 0.3; xrandr --output Virtual-1 --preferred 2>/dev/null;; esac; done"
```

Source: `assets/vbox-autoresize.desktop:4`. VBox GA 7.2.6 kernel modules build cleanly on Debian 13 kernel 6.12 but the GA service that drives `VBoxClient --vmsvga-session` silently fails (VirtualBox/virtualbox#568). This XDG autostart monitors RandR events and applies `xrandr --preferred` on each `ScreenChangeNotify`.

## Key Decisions

- **Screen lock disabled**: re-enabling it causes `VBoxClient --clipboard` to terminate on X-event storms during lock/unlock (Oracle VBox #5266/#19234, unfixed since 2009). The watchdog service provides recovery IF locking is re-enabled. Source: `scripts/40-xfce-base.sh:43-62`.
- **256 MB VRAM ceiling is absolute**: VMSVGA silently clamps values above 256 MB (VBox forum #107806). "GPU memory" is just host RAM used as framebuffer — there is no real GPU acceleration. Source: `Vagrantfile:104`.
- **3D acceleration prohibition is absolute**: enabling it regresses BOTH compositing (black screen after login) AND Chrome GPU probing. Source: `CLAUDE.md`.
- **VBoxClient CPU cost is negligible**: `VBoxClient --clipboard --nodaemon` blocks on an HGCM ioctl — it is not a polling loop. Steady-state cost is one extra pid + a few KB RSS. Source: `plans/0001-clipboard-supervisor.md:45-49`.

## Gotchas

**Black screen from boot**: wrong graphics controller (`vboxsvga` instead of `vmsvga`). `vboxvideo` driver does not load on Debian 13; `vmwgfx` (VMSVGA) is in the mainline kernel. Fix: confirm `Vagrantfile:105` has `vmsvga`.

**Black screen after login (compositing)**: either 3D acceleration was enabled, or `vblank_mode` was removed from `assets/xfwm4.xml`. Verify VMSVGA, confirm no `--accelerate3d on`, confirm `vblank_mode=off` in xfwm4.xml.

**Clipboard stops working**: `VBoxClient --clipboard` terminated silently (Oracle bug #5266). Recovery: `systemctl --user restart vbox-clipboard.service`. If recovery fails repeatedly, check that the WantedBy symlinks in `~/.config/systemd/user/default.target.wants/` exist.

**Auto-resize not working after VM reboot**: the xev-based `vbox-autoresize.desktop` autostart must have loaded. Check `systemctl --user status` and that `assets/vbox-autoresize.desktop` was deployed by `scripts/51-vbox-autoresize.sh`.

**Clipboard / `/vagrant` mount / auto-resize all dead after `apt upgrade` + reboot**: a kernel bump leaves the GA modules (`vboxguest`, `vboxsf`, `vboxvideo`) unbuilt for the new kernel. The `vboxadd.service` boot rebuild and the dkms kernel-postinst rebuild both need `linux-headers-amd64` + `dkms` + a compiler — but `bento/debian-13` ships GA pre-installed, so the `30-guest-additions.sh` skip-guard once bypassed installing them, and `apt autoremove` strips them (auto-marked on the base box), silently disarming the self-heal. `30-guest-additions.sh` now installs and `apt-mark manual`s `linux-headers-amd64 dkms` **unconditionally, before the guard**. Recover a box that already lost them: `sudo apt install linux-headers-amd64 dkms && sudo /sbin/rcvboxadd setup` (rebuilds modules for all installed kernels), or `FORCE_REINSTALL=1 vagrant provision`.

**Chrome freezing**: managed policy file missing or not applied at Machine scope. Verify `chrome://policy` shows `HardwareAccelerationModeEnabled = false` with Machine scope and status OK. If absent, re-run `scripts/40-xfce-base.sh` or check `fetch_asset chrome-policy-no-gpu.json`.

**`systemctl --user enable` during provisioning**: fails with "Failed to connect to bus: No such file or directory" because no user manager session exists. Use the WantedBy symlink pattern instead.

**VRAM above 256 MB silently ignored**: no error in `vagrant up` output — VirtualBox clamps at 256 MB. Setting 512 MB does nothing. Source: `Vagrantfile:104`.

## References

- `references/clipboard-supervisor-architecture.md` — Read when: debugging clipboard failures, understanding the three-layer fix in detail, tracing the D-Bus watchdog flow, or adding a new supervised VBoxClient helper.
- `references/vmsvga-graphics-rationale.md` — Read when: tempted to change the graphics controller, investigating black screen root cause, or understanding why vblank_mode=off is required alongside compositing.
- `references/chrome-managed-policy.md` — Read when: Chrome is freezing, verifying policy deployment, or understanding why managed policy is used instead of command-line flags.
