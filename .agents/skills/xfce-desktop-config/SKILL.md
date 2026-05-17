---
name: xfce-desktop-config
description: Use when shaping the XFCE/LightDM/GTK guest experience without an active D-Bus session: writing xfconf channel XML for xfwm4.xml, xsettings.xml, xfce4-panel.xml, xfce4-power-manager.xml, using dconf compile (NOT dconf load — provisioning has no session bus) to build ~/.config/dconf/user from keyfiles for Tilix and Mousepad, rewriting tilix.dconf section headers from [/] to [com/gexperts/Tilix], configuring LightDM autologin with runtime detection of xfce.desktop vs xfce4.desktop, deploying lightdm-gtk-greeter.conf (Arc-Dark + Papirus-Dark + Noto Sans), shadowing light-locker.desktop with Hidden=true, working around the Papirus-Dark icon inheritance gap (inherits from breeze-dark,hicolor) by symlinking utilities-terminal.svg into the user-XDG hicolor overlay, holding Tilix profile UUID 2b7c4080-0ddd-46c5-8f23-563fd3ba789d, and symlinking /etc/profile.d/vte-2.91.sh to vte.sh for OSC 7 / prompt-markers. Not for VirtualBox VMSVGA gotchas, shell-script conventions, or installer trust verification.
user-invocable: false
metadata:
  pattern: tool-wrapper
  source_files:
    - "scripts/40-xfce-base.sh"
    - "scripts/41-xfce-theme.sh"
    - "scripts/60-apps-tilix-mousepad.sh"
    - "assets/xfwm4.xml"
    - "assets/xsettings.xml"
    - "assets/xfce4-panel.xml"
    - "assets/xfce4-power-manager.xml"
    - "assets/tilix.dconf"
    - "assets/lightdm-gtk-greeter.conf"
  updated: "2026-05-17"
---

# XFCE Desktop Config

<constraint>
Use `dconf compile` (NOT `dconf load` or `gsettings set`) to write Tilix and Mousepad settings during provisioning. No D-Bus session is available; `dconf load` and `gsettings set` require the session bus and consistently fail under bento/debian-13's `tmp.mount`. Source: `scripts/60-apps-tilix-mousepad.sh:12-31`.
</constraint>

<constraint>
`dconf compile` REPLACES the entire output database. Do NOT add `|| true` to the compile command — a silent failure means Tilix opens with default ugly theme, which looks like a broken box. Fail loud. Source: `scripts/60-apps-tilix-mousepad.sh:59-62`.
</constraint>

<constraint>
Keep the Tilix profile UUID fixed at `2b7c4080-0ddd-46c5-8f23-563fd3ba789d`. Changing it breaks the link between `default-profile`, `profile-list`, and the `[profiles/UUID]` entry in the compiled dconf database. Source: `assets/tilix.dconf:4-7`.
</constraint>

<constraint>
LightDM `user-session` and `autologin-session` MUST match the actual `.desktop` filename in `/usr/share/xsessions/`. Detect at runtime — do not hardcode `xfce` or `xfce4`. Source: `scripts/40-xfce-base.sh:15-24`.
</constraint>

## When to Use

- Changing XFCE theme, fonts, or window manager settings.
- Modifying Tilix or Mousepad dconf settings.
- Changing LightDM autologin user or session.
- Investigating why Tilix shows "Configuration Issue Detected".
- Debugging Papirus-Dark icon warnings.
- Adding a new dconf keyfile for a GTK app.
- Understanding why xfconf XML writes to two different paths.
- Deploying a new XFCE panel config.

## Core Patterns

### LightDM autologin with runtime session detection

```bash
XFCE_SESSION="xfce"
[ -f /usr/share/xsessions/xfce.desktop ] || XFCE_SESSION="xfce4"
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<LIGHTDM
[Seat:*]
autologin-guest=false
autologin-user=vagrant
autologin-user-timeout=0
user-session=${XFCE_SESSION}
autologin-session=${XFCE_SESSION}
LIGHTDM
```

Source: `scripts/40-xfce-base.sh:15-24`. Between Debian versions, XFCE ships as `xfce.desktop` or `xfce4.desktop` — hardcoding either name breaks autologin on the other.

### XFCE config XML — two write paths

```bash
# System default (loaded before user config on first login)
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
fetch_asset xfce4-panel.xml /etc/xdg/xfce4/panel/default.xml
cp /etc/xdg/xfce4/panel/default.xml \
   /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

# Per-user values (win over system defaults at runtime)
mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml
fetch_asset xfwm4.xml  /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
fetch_asset xsettings.xml /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
```

Source: `scripts/40-xfce-base.sh:35-49`, `scripts/41-xfce-theme.sh:18-19`. xfconfd reads channel XML files from both paths; user config wins at runtime. Both paths must use the exact xfconf channel XML format (not gsettings schema format).

### dconf compile — the correct provisioning path

```bash
KEYFILES_DIR=$(mktemp -d)
trap 'rm -rf "$KEYFILES_DIR" /tmp/tilix.dconf' EXIT

# Mousepad settings as keyfile
cat >"$KEYFILES_DIR/00-mousepad" <<'EOF'
[org/xfce/mousepad/preferences/view]
show-line-numbers=true
color-scheme='solarized-dark'
EOF

# Tilix: fetch dconf file and rewrite section headers for keyfile syntax
fetch_asset tilix.dconf /tmp/tilix.dconf
sed -e 's|^\[/\]$|[com/gexperts/Tilix]|' \
    -e 's|^\[\(profiles/[^]]*\)\]$|[com/gexperts/Tilix/\1]|' \
    /tmp/tilix.dconf > "$KEYFILES_DIR/10-tilix"

install -d -o vagrant -g vagrant /home/vagrant/.config/dconf
chown -R vagrant:vagrant "$KEYFILES_DIR"
runuser -u vagrant -- dconf compile /home/vagrant/.config/dconf/user "$KEYFILES_DIR"
```

Source: `scripts/60-apps-tilix-mousepad.sh:38-62`. `dconf compile OUTPUT KEYFILEDIR` writes a binary GVDB directly to disk — no bus required.

### Section-header rewrite: dconf-load → keyfile syntax

```bash
sed -e 's|^\[/\]$|[com/gexperts/Tilix]|' \
    -e 's|^\[\(profiles/[^]]*\)\]$|[com/gexperts/Tilix/\1]|' \
    /tmp/tilix.dconf > "$KEYFILES_DIR/10-tilix"
```

Source: `scripts/60-apps-tilix-mousepad.sh:53-55`. `assets/tilix.dconf` uses dconf-load syntax (`[/]` = subtree root). `dconf compile` requires keyfile syntax with absolute GSettings paths. Without this rewrite, the compiled database has incorrect paths and Tilix ignores it.

Input:
```
[/]
default-profile='2b7c4080-0ddd-46c5-8f23-563fd3ba789d'
[profiles/2b7c4080-0ddd-46c5-8f23-563fd3ba789d]
```
Output:
```
[com/gexperts/Tilix]
default-profile='2b7c4080-0ddd-46c5-8f23-563fd3ba789d'
[com/gexperts/Tilix/profiles/2b7c4080-0ddd-46c5-8f23-563fd3ba789d]
```

Source: `assets/tilix.dconf:1-7`

### Papirus-Dark icon gap overlay

```bash
ICON_DST=/home/vagrant/.local/share/icons/hicolor
ICON_SRC=/usr/share/icons/Papirus
for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  mkdir -p "$ICON_DST/$size/apps"
  ln -sfn "$ICON_SRC/$size/apps/utilities-terminal.svg" \
          "$ICON_DST/$size/apps/utilities-terminal.svg"
done
mkdir -p "$ICON_DST/scalable/apps"
ln -sfn "$ICON_SRC/64x64/apps/utilities-terminal.svg" \
        "$ICON_DST/scalable/apps/utilities-terminal.svg"
[ -e "$ICON_DST/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DST/"
gtk-update-icon-cache -q -f "$ICON_DST" >/dev/null 2>&1 || true
```

Source: `scripts/41-xfce-theme.sh:33-47`. Papirus-Dark inherits from `breeze-dark,hicolor` (NOT Papirus), so `utilities-terminal.svg` is unreachable. The hicolor user overlay provides the icon to any active theme without modifying package-managed files.

### Screen lock disable (light-locker override)

```bash
mkdir -p /home/vagrant/.config/autostart
cat > /home/vagrant/.config/autostart/light-locker.desktop <<'LL'
[Desktop Entry]
Type=Application
Name=Light Locker (disabled)
Exec=/bin/true
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=false
LL
```

Source: `scripts/40-xfce-base.sh:53-62`. User-level autostart overrides `/etc/xdg/autostart/` and survives `apt upgrade light-locker`. Screen lock causes `VBoxClient --clipboard` to terminate (Oracle VBox #5266/#19234).

### VTE shell integration for Tilix

```bash
if [[ -f /etc/profile.d/vte-2.91.sh && ! -e /etc/profile.d/vte.sh ]]; then
  ln -s vte-2.91.sh /etc/profile.d/vte.sh
fi
if ! grep -q 'TILIX_ID' /home/vagrant/.bashrc 2>/dev/null; then
  cat >> /home/vagrant/.bashrc <<'BASHRC_VTE'

# VTE shell integration for Tilix (OSC 7 cwd + prompt markers)
if [ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]; then
  . /etc/profile.d/vte.sh
fi
BASHRC_VTE
fi
```

Source: `scripts/60-apps-tilix-mousepad.sh:71-83`. Debian ships `/etc/profile.d/vte-2.91.sh` (login-only); Tilix spawns interactive non-login shells, so the hooks never load and Tilix shows "Configuration Issue Detected".

## Key Decisions

- **`dconf compile` not `dconf load`**: D-Bus session is unavailable during provisioning; `dbus-run-session` consistently failed with socket permission errors under bento/debian-13's `tmp.mount`. Source: `scripts/60-apps-tilix-mousepad.sh:12-26`.
- **Fixed Tilix profile UUID**: random UUIDs on first launch would not match `default-profile` and `profile-list` in the pre-compiled database. Source: `assets/tilix.dconf:4`.
- **xfconf XML to two paths**: `/etc/xdg/` sets system defaults; `~/.config/xfce4/` sets per-user overrides. Both are needed — system defaults apply to new users; per-user overrides win at runtime. Source: `scripts/40-xfce-base.sh:35-49`.
- **User-level hicolor overlay**: symlinking into `~/.local/share/icons/hicolor/` is safe for `apt upgrade papirus-icon-theme` and `papirus-icon-theme` removal. Source: `scripts/41-xfce-theme.sh:33`.

## Gotchas

**`dconf compile` replaces the entire user dconf database**: any manual Tilix or Mousepad settings changed inside the VM are overwritten on the next `vagrant provision`. Unlike `dconf load` (which merges), compile writes a completely new binary database. Source: `scripts/60-apps-tilix-mousepad.sh:29-31`.

**Hardcoding `xfce` or `xfce4` in LightDM conf**: breaks autologin on the Debian version where the XFCE session has the other name. Always use the runtime detection. Source: `scripts/40-xfce-base.sh:15-16`.

**`[/]` section header in tilix.dconf**: this is dconf-load syntax. If `dconf compile` receives a keyfile with `[/]` instead of `[com/gexperts/Tilix]`, the compiled database has keys at the root path and Tilix loads its defaults instead. The sed rewrite is load-bearing. Source: `scripts/60-apps-tilix-mousepad.sh:53-55`.

**Papirus-Dark warning persists after provisioning if `gtk-update-icon-cache` fails**: the cache is optional (`|| true`), but without it the icon resolver must scan directories on each lookup — the warning still appears. The `index.theme` copy at line 44 is required for `gtk-update-icon-cache` to write a valid cache file.

**Tilix "Configuration Issue Detected"** after provisioning: the VTE symlink (`/etc/profile.d/vte.sh`) must exist AND the `~/.bashrc` append must have run. Check `scripts/60-apps-tilix-mousepad.sh:71-83`. The dialog appears because Tilix detects it's running under VTE but the VTE shell hooks aren't sourced.

## References

- `references/dconf-compile-rationale.md` — Read when: adding a new GTK/dconf-based app to provisioning, tempted to use `dconf load` or `gsettings set`, or debugging "settings not applied after provision".
- `references/papirus-dark-icon-gap.md` — Read when: seeing GTK icon warnings in Tilix, adding a new icon to the hicolor overlay, or understanding the Papirus-Dark inheritance chain.
- `references/tilix-vte-shell-integration.md` — Read when: Tilix shows "Configuration Issue Detected", adding VTE support for a new terminal, or explaining why `/etc/profile.d/` alone doesn't work.
