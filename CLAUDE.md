# Debian 13 Dev Box — Vagrant VM

## Project Overview

This repository contains a single `Vagrantfile` that provisions a complete Debian 13 (Trixie, stable) development VM with XFCE desktop, running on VirtualBox. Everything is configured via inline shell provisioning — there are no external scripts.

## Key Technical Details

- **Base box:** `bento/debian-13` (Debian 13 Trixie, stable). We use Bento's image rather than the Debian Cloud Team's `debian/trixie64` because the latter is published with the **libvirt provider only** as of 2026 ([Debian bug #1110834](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1110834) — original maintainer stepped down after Vagrant's license change, new maintainer publishes libvirt-only). We also avoid `debian/testing64` because `testing` now tracks Forky (Debian 14 dev), where packages like Tilix get auto-removed when transitive deps break. Bento ships VirtualBox/VMware/Parallels by default and is actively maintained (Debian 13.3 as of Nov 2025).
- **Hypervisor:** VirtualBox with VMSVGA graphics controller (the correct one for Linux guests; VBoxSVGA is for Windows)
- **Desktop:** XFCE 4 with LightDM (autologin as `vagrant`, password: `docks`)
- **Theme:** Arc-Dark + Papirus-Dark icons + Noto Sans font + DMZ-White cursor
- **Graphics:** VirtualBox Guest Additions built from ISO. VMSVGA uses the mainline `vmwgfx` kernel driver (no blacklisting needed). GA provides clipboard, shared folders, and auto-resize.
- **Compositor:** xfwm4 compositor is **enabled** (`use_compositing=true`) so windows get rounded corners and shadows. `vblank_mode=off` is kept because xfwm4 marks `llvmpipe`/`SVGA3D`/`virgl` as unsupported GL renderers for vblank (xfwm4 `src/compositor.c`), and VMSVGA exposes exactly those — leaving vblank at the default `auto`/`glx` would trigger "Unsupported GL renderer" warnings and unstable paths. Compositing itself is fine under VMSVGA software rendering; only VirtualBox 3D acceleration regresses it.
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

- **Black screen after login:** Historically blamed on the xfwm4 compositor, but the actual root cause was the **VBoxSVGA** graphics controller (commits `f00bff2` → `159b6bf` on 2026-04-03 — VBoxSVGA was replaced with VMSVGA, which fixed it). The compositor-disable workaround was kept defensively but is unnecessary under VMSVGA without 3D acceleration. If a black screen reappears: confirm graphics controller is VMSVGA, confirm VirtualBox 3D acceleration is **off**, and only as a last resort flip `use_compositing` to `false` in `assets/xfwm4.xml`. Keep `vblank_mode=off` regardless — see the Compositor note above.
- **Black screen from boot (no greeter):** Wrong graphics controller. Linux guests MUST use VMSVGA (not VBoxSVGA). VBoxSVGA needs vboxvideo driver which may not load; VMSVGA uses vmwgfx (mainline kernel) which works immediately.
- **Autologin not working:** Check that `autologin-session` matches the actual `.desktop` file in `/usr/share/xsessions/`. Session name detection is automatic.
- **Auto-resize not working:** VBox GA 7.2.6 fails to register the VMSVGA auto-resize path on Debian 13 Trixie — kernel modules build cleanly on 6.12, but the GA service that should drive `VBoxClient --vmsvga-session` silently fails ([VirtualBox/virtualbox#568](https://github.com/VirtualBox/virtualbox/issues/568), open). Workaround: an `xev`-based autostart script monitors RandR events and applies `xrandr --preferred` (`scripts/51-vbox-autoresize.sh`). When Oracle fixes the GA service registration, the xev workaround can be removed and native auto-resize will work.
- **Provisioning aborts early:** Check for missing `|| true` on commands that can fail (gsettings, dconf, curl). The script uses `set -euo pipefail`.
- **`apt-get upgrade` fails on `grub-pc` post-install:** Bento's `bento/debian-13` ships with an empty `grub-pc/install_devices` debconf field. When `apt-get upgrade` pulls a new `grub-pc` (e.g. `2.12-9+deb13u1`), grub-pc's postinst runs `grub-install` and aborts with "You must correct your GRUB install devices before proceeding" — `DEBIAN_FRONTEND=noninteractive` can't auto-answer an empty-by-default debconf field. The Debian Cloud Team's old `debian/*` boxes pre-seeded this; Bento's Packer template doesn't. `scripts/10-apt-repos.sh` pre-seeds `grub-pc/install_devices` (auto-detected via `lsblk`) and `grub-pc/install_devices_empty=false` *before* `apt-get upgrade`. If upgrade still fails, check that `lsblk -ndo NAME,TYPE | awk '$2=="disk"'` resolves to the actual boot disk inside the VM.
- **Screen lock breaks host↔guest clipboard:** `VBoxClient --clipboard` terminates silently on X-event storms during lock/unlock (Oracle VirtualBox [#5266](https://www.virtualbox.org/ticket/5266) / [#19234](https://www.virtualbox.org/ticket/19234), unfixed since 2009). Provisioning disables `light-locker` + DPMS via `assets/xfce4-power-manager.xml` so the lock path is never hit. If you re-enable locking (XFCE Settings → Power Manager), `vbox-clipboard-unlock-watchdog.service` listens on the D-Bus `org.freedesktop.ScreenSaver` signal and kicks the supervised clipboard helper on unlock — belt-and-braces on top of the `Restart=always` supervisor from `scripts/50-vboxclient-supervisor.sh`.
- **Chrome freezes inside the VM (`next dev` + Chrome + Claude):** VMSVGA has no real GPU; Chrome's hardware-accelerated paths probe it, fall through fallbacks, and deadlock under load (Oracle VirtualBox [#15417](https://www.virtualbox.org/ticket/15417)). Provisioning installs `/etc/opt/chrome/policies/managed/no-gpu.json` with `HardwareAccelerationModeEnabled=false` (from `assets/chrome-policy-no-gpu.json`, wired in `scripts/40-xfce-base.sh`). Verify at `chrome://policy` (row present, `Machine` scope, status OK) and `chrome://gpu` — every "Graphics Feature Status" row should read "Software only" or "Disabled". Do **not** enable VirtualBox 3D acceleration as a workaround; it regresses xfwm4 compositing (black screen after login) and makes Chrome worse on Linux guests.
- **VRAM ceiling:** 256 MB is the hard maximum for VMSVGA — VirtualBox silently clamps higher values ([VBox forum #107806](https://forums.virtualbox.org/viewtopic.php?t=107806), [#81370](https://forums.virtualbox.org/viewtopic.php?t=81370)). "GPU memory" is just host RAM used as a framebuffer; it is not real GPU acceleration. Raising it further is not possible without switching graphics controllers (VBoxSVGA is Windows-only; VBoxVGA 3D is deprecated since 6.1), both of which regress the clipboard/auto-resize behavior we rely on.
