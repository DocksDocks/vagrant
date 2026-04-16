#!/usr/bin/env bash
# 40-xfce-base.sh — LightDM autologin + XFCE panel/dock + Chrome as default browser.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  # Local-dev mode: the repo is mounted at /vagrant on the guest (default shared folder).
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}

# ── LightDM autologin ───────────────────────────────────
mkdir -p /etc/lightdm/lightdm.conf.d
# Detect actual XFCE session name (varies between Debian versions)
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

getent group autologin >/dev/null || groupadd autologin
usermod -aG autologin vagrant
systemctl set-default graphical.target

# LightDM greeter com Arc-Dark + Papirus (tela de login)
fetch_asset lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf

# ── Painel XFCE (layout Ubuntu-like: top bar + bottom dock) ──
# Escrito em /etc/xdg para ser usado como default no primeiro login
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
mkdir -p /etc/xdg/xfce4/panel

fetch_asset xfce4-panel.xml /etc/xdg/xfce4/panel/default.xml
# Copia para xfconf xdg path (onde xfconfd lê no primeiro login)
cp /etc/xdg/xfce4/panel/default.xml \
   /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

# ── Disable screen lock + idle blank + DPMS ─────────────
# VM autologs in as `vagrant`; locking only breaks VBoxClient --clipboard
# (upstream Oracle bugs #5266 / #19234, unfixed) and adds no real security.
# Re-enable via XFCE Settings → Power Manager if you need it, and the
# vbox-clipboard-unlock-watchdog user unit will kick the helper on unlock.
fetch_asset xfce4-power-manager.xml \
  /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml

# User-level autostart override always wins over /etc/xdg/autostart and is
# apt-upgrade-safe (we don't overwrite the light-locker package's file).
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

# ── Docklike: apps fixos (Chrome, Thunar, Terminal, Mousepad) ──
fetch_asset docklike.rc /etc/xdg/xfce4/panel/docklike.rc
# Copia com ID do plugin para cobertura completa
cp /etc/xdg/xfce4/panel/docklike.rc /etc/xdg/xfce4/panel/docklike-10.rc

# ── Chrome como navegador padrão ────────────────────────
mkdir -p /home/vagrant/.config/xfce4/helpers
fetch_asset google-chrome-helper.desktop /home/vagrant/.config/xfce4/helpers/google-chrome.desktop

echo "WebBrowser=google-chrome" > /home/vagrant/.config/xfce4/helpers.rc

fetch_asset mimeapps.list /home/vagrant/.config/mimeapps.list

cp /usr/share/applications/google-chrome.desktop \
   /usr/share/applications/exo-web-browser.desktop 2>/dev/null || true

# ── Chrome: disable hardware acceleration (VBox #15417) ─
# VMSVGA has no real GPU. Chrome's GPU process probes it and deadlocks under
# load (e.g. `next dev` + Chrome + Claude). Managed policy is the official
# Google mechanism — survives apt upgrades, applies to every launch path.
fetch_asset chrome-policy-no-gpu.json /etc/opt/chrome/policies/managed/no-gpu.json
chmod 0644 /etc/opt/chrome/policies/managed/no-gpu.json

chown -R vagrant:vagrant /home/vagrant/.config
