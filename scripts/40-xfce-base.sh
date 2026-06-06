#!/usr/bin/env bash
# 40-xfce-base.sh — LightDM autologin + XFCE panel/dock + Chrome as default browser.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

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

# LightDM greeter com Tokyo Night GTK + Papirus (tela de login)
fetch_asset lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf

# ── Painel XFCE (single bottom panel: whiskermenu + dock + systray + clock) ──
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

# ── Navegador padrão (dependente da arquitetura) ────────
# amd64: Google Chrome. arm64 (Apple Silicon / UTM): chromium do Debian,
# pois o Chrome não tem build Linux para arm64 (ver 10/20-*.sh).
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  BROWSER_DESKTOP=google-chrome.desktop
  BROWSER_HELPER=google-chrome
else
  BROWSER_DESKTOP=chromium.desktop
  BROWSER_HELPER=chromium
fi

# ── Docklike: apps fixos (navegador, Thunar, Terminal, VS Code) ──
fetch_asset docklike.rc /etc/xdg/xfce4/panel/docklike.rc
sed -i "s/google-chrome\.desktop/${BROWSER_DESKTOP}/g" /etc/xdg/xfce4/panel/docklike.rc
# Copia com ID do plugin para cobertura completa
cp /etc/xdg/xfce4/panel/docklike.rc /etc/xdg/xfce4/panel/docklike-10.rc

# ── Navegador como padrão ───────────────────────────────
mkdir -p /home/vagrant/.config/xfce4/helpers
if [ "$BROWSER_HELPER" = "google-chrome" ]; then
  fetch_asset google-chrome-helper.desktop /home/vagrant/.config/xfce4/helpers/google-chrome.desktop
else
  # Helper XFCE p/ chromium (mesmo formato do helper do Chrome em assets/).
  cat > /home/vagrant/.config/xfce4/helpers/chromium.desktop <<'CHROMIUM'
[Desktop Entry]
X-XFCE-Binaries=chromium;chromium-browser;
X-XFCE-Category=WebBrowser
X-XFCE-Commands=%B;%B;
X-XFCE-CommandsWithParameter=%B "%s";%B "%s";
Type=X-XFCE-Helper
Name=Chromium
Icon=chromium
CHROMIUM
fi

echo "WebBrowser=${BROWSER_HELPER}" > /home/vagrant/.config/xfce4/helpers.rc

fetch_asset mimeapps.list /home/vagrant/.config/mimeapps.list
sed -i "s/google-chrome\.desktop/${BROWSER_DESKTOP}/g" /home/vagrant/.config/mimeapps.list

cp "/usr/share/applications/${BROWSER_DESKTOP}" \
   /usr/share/applications/exo-web-browser.desktop 2>/dev/null || true

# ── Chrome: disable hardware acceleration (VBox #15417) ─
# VMSVGA has no real GPU. Chrome's GPU process probes it and deadlocks under
# load (e.g. `next dev` + Chrome + Claude). Managed policy is the official
# Google mechanism — survives apt upgrades, applies to every launch path.
# Específico do Chrome + VMSVGA: só no caminho amd64/VirtualBox. Em arm64/UTM
# não há Chrome nem VMSVGA, então a policy não se aplica.
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  fetch_asset chrome-policy-no-gpu.json /etc/opt/chrome/policies/managed/no-gpu.json
  chmod 0644 /etc/opt/chrome/policies/managed/no-gpu.json
fi

# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.
