#!/usr/bin/env bash
# 41-xfce-theme.sh — XFCE theme (Arc-Dark + Papirus + Noto Sans) + GTK3 headerbar CSS.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" ]]; then
    install -D -m 0644 "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}

# ── GTK3 headerbar button fix (Arc-Dark CSD styling) ──
mkdir -p /home/vagrant/.config/gtk-3.0
fetch_asset gtk.css /home/vagrant/.config/gtk-3.0/gtk.css
chown -R vagrant:vagrant /home/vagrant/.config/gtk-3.0

# ── Tema visual (Arc-Dark + Papirus + Noto Sans) ────────
mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml

fetch_asset xsettings.xml       /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
fetch_asset xfwm4.xml           /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
fetch_asset xfce4-terminal.xml  /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml

chown -R vagrant:vagrant /home/vagrant/.config/xfce4
