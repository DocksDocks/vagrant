# Debian 13 Dev Box — Vagrant VM

## Project Overview

This repository contains a single `Vagrantfile` that provisions a complete Debian 13 (Trixie/testing) development VM with XFCE desktop, running on VirtualBox. Everything is configured via inline shell provisioning — there are no external scripts.

## Key Technical Details

- **Base box:** `debian/testing64` (Debian Trixie)
- **Hypervisor:** VirtualBox with VBoxSVGA graphics controller
- **Desktop:** XFCE 4 with LightDM (autologin as `vagrant`, password: `docks`)
- **Theme:** Arc-Dark + Papirus-Dark icons + Noto Sans font + DMZ-White cursor
- **Graphics:** VirtualBox Guest Additions built from ISO, vmwgfx blacklisted to avoid conflict with vboxvideo
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

Git, GitHub CLI (gh), Python 3 + pip + venv, PHP 8.4 CLI + extensions, Composer, Docker + Compose + Buildx, Node.js LTS (nvm), npm, pnpm, Claude Code, ShellCheck, jq, ripgrep, build-essential, Tilix, fzf, bat, fd-find, htop, tree, direnv, Lazygit, Google Chrome.

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

## Common Issues

- **Black screen after login:** Caused by xfwm4 compositor + VirtualBox VBoxSVGA. Fix: ensure `use_compositing=false` in xfwm4.xml
- **Autologin not working:** Check that `autologin-session` matches the actual `.desktop` file in `/usr/share/xsessions/`. Session name detection is automatic.
- **Guest Additions warning:** "kernel modules were not reloaded" during provisioning is expected — the new kernel boots after reboot and GA works correctly then.
- **Provisioning aborts early:** Check for missing `|| true` on commands that can fail (gsettings, dconf, curl). The script uses `set -euo pipefail`.
