# Debian 13 Dev Box — Vagrant VM

## Project Overview

This repository contains a single `Vagrantfile` that provisions a complete Debian 13 (Trixie, stable) development VM with XFCE desktop, running on VirtualBox. Everything is configured via inline shell provisioning — there are no external scripts.

## Key Technical Details

- **Base box:** `debian/trixie64` (Debian 13, stable). We pin to Trixie rather than `debian/testing64` because `testing` now tracks Forky (Debian 14 dev), where packages like Tilix get auto-removed when transitive deps break.
- **Hypervisor:** VirtualBox with VMSVGA graphics controller (the correct one for Linux guests; VBoxSVGA is for Windows)
- **Desktop:** XFCE 4 with LightDM (autologin as `vagrant`, password: `docks`)
- **Theme:** Arc-Dark + Papirus-Dark icons + Noto Sans font + DMZ-White cursor
- **Graphics:** VirtualBox Guest Additions built from ISO. VMSVGA uses the mainline `vmwgfx` kernel driver (no blacklisting needed). GA provides clipboard, shared folders, and auto-resize.
- **Compositor:** xfwm4 compositor is **disabled** (`use_compositing=false`, `vblank_mode=off`) — required for VirtualBox compatibility to prevent black screen after login
- **Shell provisioning:** Uses `set -euo pipefail`, so any unhandled error aborts the entire provisioning. Commands that may fail should use `|| true`.

## Architecture

The Vagrantfile is self-contained (~515 lines) with this structure:

1. **Host detection** (lines 1-51): Auto-detect RAM/CPUs/audio driver
2. **VirtualBox config** (lines 62-76): VM resources, graphics, clipboard, audio
3. **Shell provisioner** (lines 79-512): All provisioning in a single inline script
   - System update + external repos (Chrome, Docker, GitHub CLI)
   - Package installation (single `apt-get install` with all packages)
   - VirtualBox Guest Additions installation from ISO
   - LightDM autologin configuration (dynamic session name detection)
   - XFCE theme/panel/dock configuration via XML files
   - Application configs (Tilix via dconf, Mousepad via gsettings)
   - Node.js (nvm) + pnpm + Claude Code installation
   - Lazygit, SSH key generation, git config
   - SSOT `.claude` config sync from `DocksDocks/public`
   - Reboot on first provision to activate graphical target

## Important Patterns

- **XFCE config:** Written as XML files to `~/.config/xfce4/xfconf/xfce-perchannel-xml/` and `/etc/xdg/xfce4/`
- **Tilix config:** Uses `dconf load` (not gsettings) because Tilix schemas have compilation issues. Profiles use a fixed UUID.
- **LightDM session:** Session name is detected at runtime (`xfce` vs `xfce4`) since it varies between Debian versions
- **Error handling:** gsettings/dconf commands use `|| true` to prevent `set -e` from aborting provisioning on non-critical config failures
- **Idempotent:** The script can run multiple times safely. Reboot only triggers on first provision (checks `/var/lib/vagrant-provisioned`).

## Installed Tools

Git, GitHub CLI (gh), Python 3 + pip + venv, PHP 8.4 CLI + extensions, Composer, Docker + Compose + Buildx, Node.js LTS (nvm), npm, pnpm, Claude Code, ShellCheck, jq, ripgrep, build-essential, Tilix, fzf, bat, fd-find, htop, btop, tree, direnv, Lazygit, superfile (spf), JetBrainsMono Nerd Font, Google Chrome.

## Testing Changes

To test Vagrantfile changes:
```bash
vagrant destroy -f && vagrant up
```

For non-destructive re-provisioning:
```bash
vagrant provision
```

Note: The first `vagrant up` takes several minutes (package downloads). Subsequent `vagrant up` after `vagrant halt` boots in seconds without re-provisioning.

### Re-provisioning is idempotent

`scripts/30-guest-additions.sh`, `scripts/65-superfile-fonts.sh`, and `scripts/70-nodejs-claude.sh` detect existing installs and skip them on re-provision — those are the scripts with real network/build cost. apt install is already idempotent in practice (already-installed packages take milliseconds).

To force a full re-install of Guest Additions, the Nerd Font, superfile, nvm, Node, pnpm, and Claude Code:
```bash
FORCE_REINSTALL=1 vagrant provision
```
Use this when upgrading tool versions or recovering from a broken install.

## Common Issues

- **Black screen after login:** Caused by xfwm4 compositor + VirtualBox virtual GPU. Fix: ensure `use_compositing=false` and `vblank_mode=off` in xfwm4.xml
- **Black screen from boot (no greeter):** Wrong graphics controller. Linux guests MUST use VMSVGA (not VBoxSVGA). VBoxSVGA needs vboxvideo driver which may not load; VMSVGA uses vmwgfx (mainline kernel) which works immediately.
- **Autologin not working:** Check that `autologin-session` matches the actual `.desktop` file in `/usr/share/xsessions/`. Session name detection is automatic.
- **Auto-resize not working:** VBox GA 7.2.6 fails to register the VMSVGA auto-resize path on Debian 13 Trixie — kernel modules build cleanly on 6.12, but the GA service that should drive `VBoxClient --vmsvga-session` silently fails ([VirtualBox/virtualbox#568](https://github.com/VirtualBox/virtualbox/issues/568), open). Workaround: an `xev`-based autostart script monitors RandR events and applies `xrandr --preferred` (`scripts/51-vbox-autoresize.sh`). When Oracle fixes the GA service registration, the xev workaround can be removed and native auto-resize will work.
- **Provisioning aborts early:** Check for missing `|| true` on commands that can fail (gsettings, dconf, curl). The script uses `set -euo pipefail`.
- **Screen lock breaks host↔guest clipboard:** `VBoxClient --clipboard` terminates silently on X-event storms during lock/unlock (Oracle VirtualBox [#5266](https://www.virtualbox.org/ticket/5266) / [#19234](https://www.virtualbox.org/ticket/19234), unfixed since 2009). Provisioning disables `light-locker` + DPMS via `assets/xfce4-power-manager.xml` so the lock path is never hit. If you re-enable locking (XFCE Settings → Power Manager), `vbox-clipboard-unlock-watchdog.service` listens on the D-Bus `org.freedesktop.ScreenSaver` signal and kicks the supervised clipboard helper on unlock — belt-and-braces on top of the `Restart=always` supervisor from `scripts/50-vboxclient-supervisor.sh`.
- **Chrome freezes inside the VM (`next dev` + Chrome + Claude):** VMSVGA has no real GPU; Chrome's hardware-accelerated paths probe it, fall through fallbacks, and deadlock under load (Oracle VirtualBox [#15417](https://www.virtualbox.org/ticket/15417)). Provisioning installs `/etc/opt/chrome/policies/managed/no-gpu.json` with `HardwareAccelerationModeEnabled=false` (from `assets/chrome-policy-no-gpu.json`, wired in `scripts/40-xfce-base.sh`). Verify at `chrome://policy` (row present, `Machine` scope, status OK) and `chrome://gpu` — every "Graphics Feature Status" row should read "Software only" or "Disabled". Do **not** enable VirtualBox 3D acceleration as a workaround; it regresses the xfwm4 compositor black-screen issue and makes Chrome worse on Linux guests.
- **VRAM ceiling:** 256 MB is the hard maximum for VMSVGA — VirtualBox silently clamps higher values ([VBox forum #107806](https://forums.virtualbox.org/viewtopic.php?t=107806), [#81370](https://forums.virtualbox.org/viewtopic.php?t=81370)). "GPU memory" is just host RAM used as a framebuffer; it is not real GPU acceleration. Raising it further is not possible without switching graphics controllers (VBoxSVGA is Windows-only; VBoxVGA 3D is deprecated since 6.1), both of which regress the clipboard/auto-resize behavior we rely on.
