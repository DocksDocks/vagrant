#!/usr/bin/env bash
# 20-packages.sh — batch apt install + Composer + docker group + first-run password.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Instalação em lote ──────────────────────────────────
echo ">> Instalando todos os pacotes..."
apt-get install -y -qq \
  git jq yq ripgrep build-essential tilix libharfbuzz-gobject0 wget zip unzip shellcheck rsync dconf-cli \
  fd-find fzf bat htop btop tree direnv \
  python3 python3-pip python3-venv \
  xfce4 \
  xfce4-notifyd xfce4-screenshooter \
  xfce4-whiskermenu-plugin xfce4-docklike-plugin xfce4-pulseaudio-plugin xfce4-taskmanager \
  lightdm lightdm-gtk-greeter \
  dbus-x11 xdg-utils xclip \
  pulseaudio alsa-utils \
  fonts-noto-color-emoji \
  arc-theme papirus-icon-theme fonts-noto fonts-noto-core dmz-cursor-theme sassc \
  gh code \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ── PHP 8.4 (versão fixada em ambas as arquiteturas) ────
# PHP 8.4 é requisito do projeto. Em vez dos metapacotes php-* (que seguem o
# default do Debian: 8.4 no Trixie/amd64, mas 8.2 no Bookworm/arm64), instalamos
# os pacotes versionados php8.4-*. São nativos no Trixie e vêm do repo Sury no
# Bookworm (configurado em 10-apt-repos.sh) — garantindo 8.4 também no box
# arm64/UTM, e fixando 8.4 no amd64 mesmo se o default do Debian subir depois.
# Instalado antes do Composer, que precisa do php CLI.
apt-get install -y -qq \
  php8.4-cli php8.4-common php8.4-curl php8.4-mbstring php8.4-xml php8.4-zip php8.4-bcmath php8.4-intl

# ── Navegador + integração do hypervisor (dependente da arquitetura) ──
# O Google Chrome só publica build Linux para amd64 — instalá-lo em arm64
# abortaria o batch (sem candidato). Em arm64 (Apple Silicon / UTM) usamos o
# chromium do Debian e instalamos os agentes SPICE/QEMU (clipboard + resize via
# spice-vdagent; shutdown limpo + IP via qemu-guest-agent), já que os scripts de
# Guest Additions/clipboard do VirtualBox (30/50/51) são pulados nessa arch.
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
  apt-get install -y -qq google-chrome-stable
  # ── Dedup do repo do Chrome ───────────────────────────
  # Installing google-chrome-stable drops a deb822 source
  # (/etc/apt/sources.list.d/google-chrome.sources) that duplicates the .list we
  # already maintain in 10-apt-repos.sh, so apt warns "Target Packages is
  # configured multiple times" on every update. Chrome won't recreate it once
  # removed, so dropping it here dedups the repo for good.
  rm -f /etc/apt/sources.list.d/google-chrome.sources
else
  apt-get install -y -qq chromium spice-vdagent qemu-guest-agent
fi

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

# ── Senha do usuário vagrant (só no primeiro provisionamento) ──
# Set once, on the very first provision only — guarded by the same
# /var/lib/vagrant-provisioned sentinel that 99-finalize.sh creates at the end
# of that run. Re-provisioning never touches it, so a password you change later
# sticks.
if [ ! -f /var/lib/vagrant-provisioned ]; then
  echo 'vagrant:vagrant' | chpasswd
fi

# ── Limpeza pós-install ─────────────────────────────────
# After the batch install, /var/cache/apt/archives has a ~1 GB pile of .deb
# files we won't need again unless we reinstall. autoremove drops orphaned
# auto-installed deps; clean wipes the cached .debs themselves.
echo ">> Liberando espaço em disco após o batch install..."
apt-get -y -qq autoremove
apt-get -y -qq clean
