#!/usr/bin/env bash
# 20-packages.sh — batch apt install + Composer + docker group + vagrant password.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Instalação em lote ──────────────────────────────────
echo ">> Instalando todos os pacotes..."
apt-get install -y -qq \
  git jq ripgrep build-essential tilix libharfbuzz-gobject0 wget unzip shellcheck rsync dconf-cli \
  fd-find fzf bat htop btop tree direnv \
  wine imagemagick \
  python3 python3-pip python3-venv \
  php-cli php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl \
  xfce4 xfce4-terminal \
  xfce4-notifyd xfce4-screenshooter \
  xfce4-whiskermenu-plugin xfce4-docklike-plugin xfce4-taskmanager mousepad \
  lightdm lightdm-gtk-greeter \
  dbus-x11 xdg-utils xclip libwayland-client0 \
  pulseaudio alsa-utils \
  fonts-noto-color-emoji \
  arc-theme papirus-icon-theme fonts-noto fonts-noto-core dmz-cursor-theme \
  google-chrome-stable gh \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ── Composer ────────────────────────────────────────────
echo ">> Instalando composer..."
curl -fsSL --retry 4 --retry-delay 2 https://getcomposer.org/installer -o /tmp/composer-installer.php
php /tmp/composer-installer.php --install-dir=/usr/local/bin --filename=composer
rm -f /tmp/composer-installer.php

# ── Docker (grupo) ──────────────────────────────────────
usermod -aG docker vagrant

# ── Senha do usuário vagrant ────────────────────────────
echo 'vagrant:docks' | chpasswd
