#!/usr/bin/env bash
# 20-packages.sh — batch apt install + Composer + docker group + first-run password.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Manifesto de pacotes (compartilhados vs por-plataforma) ──
# Para não confundir, mais tarde, o que é comum e o que é específico de
# arquitetura, os pacotes ficam em listas nomeadas:
#   COMMON_PKGS   — instalados em TODAS as arquiteturas. Debian main + repos
#                   externos que publicam amd64 E arm64 (gh, code, docker).
#   PLATFORM_PKGS — específicos da arquitetura (navegador + integração do
#                   hypervisor):
#                     • amd64 (VirtualBox): google-chrome-stable (sem build arm64)
#                     • arm64 (UTM): chromium + agentes SPICE/QEMU (clipboard,
#                       resize e shutdown limpo), já que os scripts VBox
#                       30/50/51 são pulados nessa arch.
#   PHP_PKGS      — PHP 8.4 versionado (nativo no Trixie, via Sury no Bookworm;
#                   ver 10-apt-repos.sh). Fixa 8.4 mesmo se o default do Debian
#                   subir depois. Instalado aqui (antes do Composer, que usa php).
# O docklike-plugin é tratado à parte (só existe no Trixie+).
ARCH=$(dpkg --print-architecture)

COMMON_PKGS="
  git jq yq ripgrep build-essential tilix libharfbuzz-gobject0 wget zip unzip shellcheck rsync dconf-cli
  fd-find fzf bat htop btop tree direnv
  python3 python3-pip python3-venv
  xfce4 xfce4-notifyd xfce4-screenshooter
  xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin xfce4-taskmanager
  lightdm lightdm-gtk-greeter
  dbus-x11 xdg-utils xclip
  pulseaudio alsa-utils
  fonts-noto-color-emoji
  arc-theme papirus-icon-theme fonts-noto fonts-noto-core dmz-cursor-theme sassc
  gh code
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

PHP_PKGS="php8.4-cli php8.4-common php8.4-curl php8.4-mbstring php8.4-xml php8.4-zip php8.4-bcmath php8.4-intl"

case "$ARCH" in
  amd64) PLATFORM_PKGS="google-chrome-stable" ;;
  arm64) PLATFORM_PKGS="chromium spice-vdagent qemu-guest-agent" ;;
  *)     PLATFORM_PKGS="chromium" ;;
esac

echo ">> Instalando pacotes (COMMON + ${ARCH} + PHP 8.4)..."
# shellcheck disable=SC2086  # word-splitting intencional das listas de pacotes
apt-get install -y -qq $COMMON_PKGS $PLATFORM_PKGS $PHP_PKGS

# Dedup do repo do Chrome (só amd64): instalar google-chrome-stable solta um
# deb822 (/etc/apt/sources.list.d/google-chrome.sources) que duplica o .list que
# já mantemos em 10-apt-repos.sh — o apt avisa "configured multiple times" a cada
# update. O Chrome não recria o arquivo, então removê-lo dedup-a o repo de vez.
[ "$ARCH" = "amd64" ] && rm -f /etc/apt/sources.list.d/google-chrome.sources

# Dock opcional: o xfce4-docklike-plugin só entrou no Debian a partir do Trixie;
# o Bookworm não o empacota. Instala se houver candidato; senão 40-xfce-base.sh
# troca o painel pelo tasklist embutido. Evita abortar com "Unable to locate".
if apt-cache show xfce4-docklike-plugin >/dev/null 2>&1; then
  apt-get install -y -qq xfce4-docklike-plugin
else
  echo ">> xfce4-docklike-plugin indisponível neste Debian — pulando (painel usa o tasklist embutido)."
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
