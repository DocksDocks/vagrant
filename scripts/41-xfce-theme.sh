#!/usr/bin/env bash
# 41-xfce-theme.sh — XFCE theme (Arc-Dark + Papirus + Noto Sans) + GTK3 headerbar CSS.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# ── GTK3 headerbar button fix (Arc-Dark CSD styling) ──
mkdir -p /home/vagrant/.config/gtk-3.0
fetch_asset gtk.css /home/vagrant/.config/gtk-3.0/gtk.css

# ── Tema visual (Arc-Dark + Papirus + Noto Sans) ────────
mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml

fetch_asset xsettings.xml       /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
fetch_asset xfwm4.xml           /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.

# ── Tilix CloseDialog icon overlay ──────────────────────
# Papirus-Dark inherits from `breeze-dark,hicolor` — NOT from Papirus — so
# `utilities-terminal.svg` (which only Papirus ships) is unreachable. Tilix
# logs `[warning] closedialog.d:88: Could not load icon for 'utilities-terminal'`
# every time the "Close terminal?" dialog renders. Drop a user-XDG hicolor
# overlay symlinking each size to the corresponding Papirus icon. Hicolor is
# GTK's universal fallback theme so this resolves the icon for any active
# theme. User-scoped (~/.local/share/icons), so `apt upgrade
# papirus-icon-theme` and `papirus-icon-theme` package removal don't break it.
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
# index.theme is required for `gtk-update-icon-cache` to write a valid cache.
[ -e "$ICON_DST/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DST/"
# Run as root so we don't need a mid-script chown — 55-permissions.sh sweeps
# /home/vagrant at the end of provisioning.
gtk-update-icon-cache -q -f "$ICON_DST" >/dev/null 2>&1 || true
