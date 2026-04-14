# Debian 13 Dev Box — Vagrant VM

## Project Overview

This repository contains a single `Vagrantfile` that provisions a complete Debian 13 (Trixie/testing) development VM with XFCE desktop, running on VirtualBox. Everything is configured via inline shell provisioning — there are no external scripts.

## Key Technical Details

- **Base box:** `debian/testing64` (Debian Trixie)
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

- **Black screen after login:** Caused by xfwm4 compositor + VirtualBox virtual GPU. Fix: ensure `use_compositing=false` and `vblank_mode=off` in xfwm4.xml
- **Black screen from boot (no greeter):** Wrong graphics controller. Linux guests MUST use VMSVGA (not VBoxSVGA). VBoxSVGA needs vboxvideo driver which may not load; VMSVGA uses vmwgfx (mainline kernel) which works immediately.
- **Autologin not working:** Check that `autologin-session` matches the actual `.desktop` file in `/usr/share/xsessions/`. Session name detection is automatic.
- **Auto-resize not working:** VBox GA 7.2.6 kernel modules fail to build on kernel 6.19+ (`__flush_tlb_all` namespace error). The in-kernel `vboxguest` lacks HGCM ioctls needed by `VBoxClient --vmsvga-session`. Workaround: an `xev`-based autostart script monitors RandR events and applies `xrandr --preferred`. When Oracle fixes GA for 6.19 ([VBox #467](https://github.com/VirtualBox/virtualbox/issues/467)), the xev workaround can be removed and native auto-resize will work.
- **Guest Additions warning:** "kernel modules were not reloaded" during provisioning is expected on kernel 6.19+ — GA 7.2.6 modules fail to build due to `__flush_tlb_all` namespace change. The in-kernel vbox modules provide basic functionality. Auto-resize uses the xev workaround (see above).
- **Provisioning aborts early:** Check for missing `|| true` on commands that can fail (gsettings, dconf, curl). The script uses `set -euo pipefail`.
- **Paste silently fails in the Claude Code OAuth login prompt:** The `Paste code here if prompted >` input drops pasted content because Claude Code mishandles bracketed-paste markers (`\e[200~`…`\e[201~`) on that screen — upstream bug [anthropics/claude-code#47670](https://github.com/anthropics/claude-code/issues/47670). Normal paste (**Ctrl+Shift+V** in Tilix, **Ctrl+V** elsewhere, including the main Claude Code chat input *after* login) is **unchanged and still works** — prefer it everywhere it works. As an additive fallback, **Ctrl+Alt+V** runs `/usr/local/bin/type-clipboard` (xdotool + xclip) which *types* the clipboard as synthetic keystrokes, bypassing bracketed paste so the OAuth prompt receives the code. Because it simulates typing, it's slower than real paste and follows the current keyboard layout — use it only when normal paste fails. Remove the helper and the `<Primary><Alt>v` xfconf binding once #47670 ships.
