#!/usr/bin/env bash
# 20-packages.sh — batch apt install + Composer + docker group + vagrant password.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Instalação em lote ──────────────────────────────────
echo ">> Instalando todos os pacotes..."
apt-get install -y -qq \
  git jq yq ripgrep build-essential tilix libharfbuzz-gobject0 wget zip unzip shellcheck rsync dconf-cli \
  fd-find fzf bat htop btop tree direnv \
  python3 python3-pip python3-venv \
  php-cli php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl \
  xfce4 \
  xfce4-notifyd xfce4-screenshooter \
  xfce4-whiskermenu-plugin xfce4-docklike-plugin xfce4-pulseaudio-plugin xfce4-taskmanager mousepad \
  lightdm lightdm-gtk-greeter \
  dbus-x11 xdg-utils xclip \
  pulseaudio alsa-utils \
  fonts-noto-color-emoji \
  arc-theme papirus-icon-theme fonts-noto fonts-noto-core dmz-cursor-theme \
  google-chrome-stable gh \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ── Composer ────────────────────────────────────────────
# Verify the installer's SHA-384 against the canonical hash published at
# composer.github.io/installer.sig before running it as root. Without this,
# a compromised CDN or MITM could ship arbitrary PHP that we'd execute with
# full privileges. Pattern follows getcomposer.org's official docs.
echo ">> Instalando composer..."
COMPOSER_INSTALLER=/tmp/composer-installer.php
curl -fsSL --retry 4 --retry-delay 2 https://getcomposer.org/installer -o "$COMPOSER_INSTALLER"
EXPECTED_SIG=$(curl -fsSL --retry 4 --retry-delay 2 https://composer.github.io/installer.sig)
ACTUAL_SIG=$(sha384sum "$COMPOSER_INSTALLER" | awk '{print $1}')
if [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
  echo "✗ Composer installer SHA-384 mismatch — refusing to run." >&2
  echo "   expected: $EXPECTED_SIG" >&2
  echo "   actual:   $ACTUAL_SIG" >&2
  rm -f "$COMPOSER_INSTALLER"
  exit 1
fi
php "$COMPOSER_INSTALLER" --install-dir=/usr/local/bin --filename=composer
rm -f "$COMPOSER_INSTALLER"

# ── Docker (grupo) ──────────────────────────────────────
usermod -aG docker vagrant

# ── Senha do usuário vagrant ────────────────────────────
echo 'vagrant:docks' | chpasswd

# ── Limpeza pós-install ─────────────────────────────────
# After the batch install, /var/cache/apt/archives has a ~1 GB pile of .deb
# files we won't need again unless we reinstall. autoremove drops orphaned
# auto-installed deps; clean wipes the cached .debs themselves.
echo ">> Liberando espaço em disco após o batch install..."
apt-get -y -qq autoremove
apt-get -y -qq clean
