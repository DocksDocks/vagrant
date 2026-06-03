# Debian 13 Dev Box — Vagrant VM

Canonical instructions for coding agents working on this project — compatible with OpenAI Codex, Claude Code (via `@AGENTS.md` import in `CLAUDE.md`), OpenCode, VS Code Copilot, GitHub Copilot CLI, and any other [agents.md](https://agents.md/)-aware tool.

## Project Overview

This repository provisions a complete Debian 13 (Trixie, stable) development VM with XFCE desktop on VirtualBox. The `Vagrantfile` is thin (~300 lines) and delegates each concern to a numbered shell script under `scripts/`, with static configs under `assets/`. Scripts are fetched from `raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/scripts/` at provision time, or read from `/vagrant/assets/` if `VAGRANT_SCRIPTS_DIR` is set (local-dev mode). See `plans/0002-split-vagrantfile.md` for the design rationale.

## Key Technical Details

- **Base box:** `bento/debian-13` (Debian 13 Trixie, stable). We use Bento's image rather than the Debian Cloud Team's `debian/trixie64` because the latter is published with the **libvirt provider only** as of 2026 ([Debian bug #1110834](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1110834) — original maintainer stepped down after Vagrant's license change, new maintainer publishes libvirt-only). We also avoid `debian/testing64` because `testing` now tracks Forky (Debian 14 dev), where packages like Tilix get auto-removed when transitive deps break. Bento ships VirtualBox/VMware/Parallels by default and is actively maintained (Debian 13.3 as of Nov 2025).
- **Hypervisor:** VirtualBox with VMSVGA graphics controller (the correct one for Linux guests; VBoxSVGA is for Windows)
- **Desktop:** XFCE 4 with LightDM (autologin as `vagrant`, password: `docks`)
- **Theme:** Arc-Dark + Papirus-Dark icons + Noto Sans font + DMZ-White cursor
- **Graphics:** VirtualBox Guest Additions built from ISO. VMSVGA uses the mainline `vmwgfx` kernel driver (no blacklisting needed). GA provides clipboard, shared folders, and auto-resize.
- **Compositor:** xfwm4 compositor is **enabled** (`use_compositing=true`) so windows get rounded corners and shadows. `vblank_mode=off` is kept because xfwm4 marks `llvmpipe`/`SVGA3D`/`virgl` as unsupported GL renderers for vblank (xfwm4 `src/compositor.c`), and VMSVGA exposes exactly those — leaving vblank at the default `auto`/`glx` would trigger "Unsupported GL renderer" warnings and unstable paths. Compositing itself is fine under VMSVGA software rendering; only VirtualBox 3D acceleration regresses it.
- **Shell provisioning:** Uses `set -euo pipefail`, so any unhandled error aborts the entire provisioning. Commands that may fail should use `|| true`.

## Architecture

The `Vagrantfile` (~300 lines) handles host-side resource detection and the VirtualBox config, then iterates `SCRIPTS = %w[...]` and registers one shell provisioner per script. Each provisioner either runs the local file (`VAGRANT_SCRIPTS_DIR=./scripts`) or fetches it from `raw.githubusercontent.com` at run time.

1. **Host detection + resource-profile menu** (Vagrantfile lines 1-196): Auto-detect RAM/CPUs/audio driver, then offer an interactive 5-tier profile menu on `vagrant up`/`reload` — an arrow-key TUI (↑/↓/`j`/`k` to move, Enter to confirm, `q`/Esc to cancel) rendered on the alternate screen. Tiers scale from a 16 GB / 8-core reference (`5.0 / 6.5 / 8.0 / 9.5 / 11.0 GB`, `4 / 5 / 6 / 6 / 6 vCPU`) and are hard-capped at 75% of host RAM and CPUs. The last choice is persisted to `.vagrant/last_profile` and pre-selected next time. Non-interactive invocations (status, ssh, provision, CI, non-tty stdin) silently use the remembered tier or `DEFAULT_TIER=2`; `VM_PROFILE=1..5` is a one-shot override that skips the menu without changing the saved choice.
2. **VirtualBox config** (Vagrantfile lines 235-249): VM resources, VMSVGA graphics, bidirectional clipboard, drag-and-drop, audio.
3. **Per-concern shell scripts** (`scripts/`):
   - `10-apt-repos.sh` — system update, timezone, grub-pc seed, external repos (Chrome, Docker, gh).
   - `15-grub-quickboot.sh` — set `GRUB_TIMEOUT=0` + `GRUB_TIMEOUT_STYLE=hidden` so the VM boots straight into Debian (skips the bento base-box's 1-second GRUB menu); idempotent, runs `update-grub` only when a value changed. Shift/Esc still reveals the menu.
   - `20-packages.sh` — batch `apt install`, Composer (with SHA-384 verification), docker group, vagrant password.
   - `30-guest-additions.sh` — VBox Guest Additions from ISO (idempotent: skips if VBoxClient is present).
   - `40-xfce-base.sh` — LightDM autologin, panel/dock layout, Chrome as default browser, Chrome no-GPU policy.
   - `41-xfce-theme.sh` — Arc-Dark + Papirus + Noto Sans + Tilix CloseDialog icon overlay.
   - `50-vboxclient-supervisor.sh` — supervised systemd --user units for clipboard/drag-n-drop + 2-min healthcheck timer (recovers the silently-dead HGCM↔X11 bridge without needing a screen-unlock signal).
   - `51-vbox-autoresize.sh` — xev-based auto-resize workaround for VBox GA #568.
   - `60-apps-tilix-mousepad.sh` — dconf-compile of Tilix + Mousepad settings, VTE shell-integration in `~/.bashrc`.
   - `65-superfile-fonts.sh` — JetBrainsMono Nerd Font + superfile (idempotent).
   - `70-nodejs-claude.sh` — nvm + Node LTS + pnpm + Claude Code + Codex CLI (idempotent). Hoists nvm's source block above the bashrc interactivity guard so `bash -lc`/IDE-spawned tooling can resolve node.
   - `80-git-ssh.sh` — `git-pull-all` (deployed via `fetch_asset bin/git-pull-all` → `/usr/local/bin`, chmod 0755), SSH key, bashrc aliases, default git config (only if not already set).
   - `85-secrets-env.sh` — scaffolds `~/.config/secrets.env` (mode 0600) and adds a guarded source line to `~/.bashrc`.
   - `90-claude-config-sync.sh` — clones `DocksDocks/public`, runs `sync.sh` for Claude/Codex config, deletes the working copy.
4. **Finalize** (Vagrantfile, inline `99-finalize`): version banner, SSH public key, reboot-on-first-provision to activate `graphical.target`.

## Important Patterns

- **XFCE config:** Written as XML files to `~/.config/xfce4/xfconf/xfce-perchannel-xml/` and `/etc/xdg/xfce4/`
- **Tilix config:** Uses `dconf load` (not gsettings) because Tilix schemas have compilation issues. Profiles use a fixed UUID.
- **LightDM session:** Session name is detected at runtime (`xfce` vs `xfce4`) since it varies between Debian versions
- **Error handling:** gsettings/dconf commands use `|| true` to prevent `set -e` from aborting provisioning on non-critical config failures
- **Idempotent:** The script can run multiple times safely. Reboot only triggers on first provision (checks `/var/lib/vagrant-provisioned`).

## Installed Tools

**CLI:** Git, GitHub CLI (gh), Python 3 + pip + venv, PHP 8.4 CLI + extensions (curl, mbstring, xml, zip, bcmath, intl), Composer (SHA-384 verified at install), Docker + Compose v2 plugin + Buildx + containerd.io, Node.js LTS (nvm), npm, pnpm, Claude Code, Codex CLI, ShellCheck, jq, yq, ripgrep, build-essential, fzf, bat (alias `bat`→`batcat`), fd-find (alias `fd`→`fdfind`), htop, btop, tree, direnv, `git-pull-all` (bulk fetch + ff-only pull across a directory tree; also runs as `git pull-all`), superfile (`spf`), wget, zip, unzip, rsync, xclip.

**Desktop:** XFCE 4 (panel, whiskermenu, docklike, taskmanager, notifyd, screenshooter), Tilix (split-pane terminal — default), Mousepad (text editor), LightDM + lightdm-gtk-greeter, Google Chrome, dbus-x11, xdg-utils, pulseaudio + alsa-utils, JetBrainsMono Nerd Font, fonts-noto + noto-color-emoji, Arc-Dark theme, Papirus + Papirus-Dark icons, DMZ-Cursor.

**Not installed by default** (install on demand): `wine`, `imagemagick`, `xfce4-terminal`. Dropped from the default set because nothing in the repo invokes them and they add noticeable provision time.

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

To force a full re-install of Guest Additions, the Nerd Font, superfile, nvm, Node, pnpm, Codex CLI, and Claude Code:
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
- **Screen lock breaks host↔guest clipboard:** `VBoxClient --clipboard` terminates silently on X-event storms during lock/unlock (Oracle VirtualBox [#5266](https://www.virtualbox.org/ticket/5266) / [#19234](https://www.virtualbox.org/ticket/19234), unfixed since 2009). Provisioning disables `light-locker` + DPMS via `assets/xfce4-power-manager.xml` so the lock path is never hit. If you re-enable locking (XFCE Settings → Power Manager), `vbox-clipboard-unlock-watchdog.service` listens on the D-Bus `org.freedesktop.ScreenSaver` signal and kicks the supervised clipboard helper on unlock — belt-and-braces on top of the `Restart=always` supervisor from `scripts/50-vboxclient-supervisor.sh`.
- **Clipboard silently dies after hours of uptime (process alive, bridge dead):** distinct failure mode of the same bug. The helper keeps running (so `Restart=always` never fires) but its HGCM↔X11 bridge degrades — `xclip -selection clipboard -o` returns "target STRING not available" and `journalctl --user -u vbox-clipboard.service` fills with `Converting VBox formats 'NONE' to '<X>' ... rc=VERR_NOT_SUPPORTED` (source-side dead) **or** `Converting VBox formats '<X>' to 'INVALID' ... rc=VERR_NOT_SUPPORTED` with `fmtX11=0` (destination-side dead) — both are sister signatures of the same bridge degradation. Recovery: `systemctl --user restart vbox-clipboard.service vbox-draganddrop.service`. Automated by `vbox-clipboard-healthcheck.timer` (2-min cadence) — scans the unit's own journal since its `ActiveEnterTimestamp` for **either** signature and restarts on hit. See `plans/0004-clipboard-healthcheck-timer.md`.
- **Chrome freezes inside the VM (`next dev` + Chrome + Claude):** VMSVGA has no real GPU; Chrome's hardware-accelerated paths probe it, fall through fallbacks, and deadlock under load (Oracle VirtualBox [#15417](https://www.virtualbox.org/ticket/15417)). Provisioning installs `/etc/opt/chrome/policies/managed/no-gpu.json` with `HardwareAccelerationModeEnabled=false` (from `assets/chrome-policy-no-gpu.json`, wired in `scripts/40-xfce-base.sh`). Verify at `chrome://policy` (row present, `Machine` scope, status OK) and `chrome://gpu` — every "Graphics Feature Status" row should read "Software only" or "Disabled". Do **not** enable VirtualBox 3D acceleration as a workaround; it regresses xfwm4 compositing (black screen after login) and makes Chrome worse on Linux guests.
- **VRAM ceiling:** 256 MB is the hard maximum for VMSVGA — VirtualBox silently clamps higher values ([VBox forum #107806](https://forums.virtualbox.org/viewtopic.php?t=107806), [#81370](https://forums.virtualbox.org/viewtopic.php?t=81370)). "GPU memory" is just host RAM used as a framebuffer; it is not real GPU acceleration. Raising it further is not possible without switching graphics controllers (VBoxSVGA is Windows-only; VBoxVGA 3D is deprecated since 6.1), both of which regress the clipboard/auto-resize behavior we rely on.
- **Arrow keys don't move the resource-profile menu on a Windows host (menu draws, `q` works, ↑/↓ do nothing):** a classic Windows console (cmd.exe / PowerShell / Windows Terminal with VT input off) never delivers arrow keys to the byte stream `read_nonblock` reads — they surface only through `getch`, as a `0x00`/`0xE0` prefix + ASCII scancode (`H`=up, `P`=down). `q`/`j`/`k`/Enter are ordinary characters, so they kept working while the arrows silently did nothing. The Vagrantfile reads keys host-aware: the ANSI-burst reader (`IO.select` + `read_nonblock`, `next_action_unix`) on Unix/macOS, a `getch`-scancode reader (`next_action_windows`/`decode_win_getch`) on Windows, selected by the `WINDOWS` constant. `1`-`5` direct selection and `j`/`k` also work everywhere as a fallback. See `plans/0005-windows-console-arrow-keys.md`.

## Skills

Skills available to agents working on this project live under `.agents/skills/`. Each skill is a directory containing a `SKILL.md` that describes when to use it. Tools that read `.agents/skills/` directly: Codex, OpenCode, VS Code Copilot, GitHub Copilot CLI. Claude Code reads the same skills via symlinks under `.claude/skills/`.

Available skills:

- `plans-adr-format` — authoring/reviewing ADRs under `plans/` (NNNN-kebab-case.md format, exemplars `0001-clipboard-supervisor.md` / `0002-split-vagrantfile.md`).
- `provisioning-script-conventions` — numbered shell scripts under `scripts/` (preamble, `fetch_asset` helper, FORCE_REINSTALL contract, idempotent ~/.bashrc appends).
- `secrets-env-convention` — `~/.config/secrets.env` (mode 0600) handling and the `85-secrets-env.sh` marker for `~/.bashrc` source guards.
- `skill-maintenance` — adding/refreshing/splitting/merging skills under `.agents/skills/`, validating frontmatter and 500-line body cap.
- `vagrantfile-orchestrator` — Vagrantfile Ruby DSL (host detection, SCRIPTS array, vb.customize, env-var forwarding to provisioners).
- `virtualbox-vmsvga-gotchas` — VMSVGA graphics, clipboard supervision (Oracle bugs #5266/#19234), autoresize (#568), Chrome no-GPU policy (#15417).
- `xfce-desktop-config` — xfconf XML channels, dconf compile (NOT load), LightDM autologin, Tilix profile UUID, Papirus icon overlay.

To add a new skill: create a new directory under `.agents/skills/<name>/` with a `SKILL.md` (frontmatter requires `name` + `description` per the [agentskills.io spec](https://agentskills.io/specification)). Mirror it as a symlink under `.claude/skills/<name>` so Claude Code discovers it too.

## Notes for nested overrides

Per the agents.md open standard, place an `AGENTS.md` inside any subdirectory that needs different rules. The closest `AGENTS.md` to the file being edited wins; explicit user prompts override everything.
