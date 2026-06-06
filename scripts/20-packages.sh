#!/usr/bin/env bash
# 20-packages.sh — batch apt install + Composer + docker group + first-run password.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Manifesto de pacotes (compartilhados vs por-plataforma) ──
# Listas nomeadas para deixar claro o que é comum e o que é específico:
#   COMMON_PKGS     — instalados em TODAS as plataformas. Debian/Ubuntu main +
#                     repos externos que publicam amd64 E arm64 (gh, code, docker).
#   PHP_PKGS        — PHP 8.4 versionado (nativo no Trixie; Sury no Bookworm; PPA
#                     ondrej/php no Ubuntu — ver 10-apt-repos.sh). Fixa 8.4 mesmo
#                     se o default da distro subir. Antes do Composer, que usa php.
#   HYPERVISOR_PKGS — só arm64/UTM: agentes SPICE/QEMU (clipboard/resize/shutdown),
#                     substituindo os scripts VBox 30/50/51 (pulados nessa arch).
# O navegador e o docklike-plugin são instalados à parte:
#   • Navegador: amd64 → google-chrome-stable; arm64 Debian → chromium (.deb);
#     arm64 Ubuntu → chromium-browser (snap, instalação tolerante).
#   • docklike: só existe no Trixie+/Ubuntu, não no Bookworm → instala se houver.
ARCH=$(dpkg --print-architecture)
# shellcheck source=/dev/null
DISTRO_ID=$(. /etc/os-release && echo "$ID")

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

# Integração do hypervisor (só arm64/UTM): agentes SPICE/QEMU para clipboard,
# resize e shutdown limpo — substituem os scripts VBox 30/50/51 (pulados).
HYPERVISOR_PKGS=""
[ "$ARCH" = "arm64" ] && HYPERVISOR_PKGS="spice-vdagent qemu-guest-agent"

# Lote confiável (somente .debs): COMMON + PHP + agentes. O navegador fica FORA
# daqui porque no Ubuntu o chromium é um snap, que pode falhar se o snapd ainda
# não estiver pronto — não queremos que isso derrube a instalação inteira.
echo ">> Instalando pacotes (COMMON + ${ARCH} + PHP 8.4)..."
# shellcheck disable=SC2086  # word-splitting intencional das listas de pacotes
apt-get install -y -qq $COMMON_PKGS $PHP_PKGS $HYPERVISOR_PKGS

# ── Navegador (instalação isolada, por distro/arch) ─────
# amd64 (VirtualBox): Google Chrome (+ dedup do deb822 duplicado que o .deb solta;
#   nosso .list em 10-apt-repos.sh é o canônico).
# arm64 Debian: chromium (.deb). arm64 Ubuntu: chromium-browser (snap) — tolerante,
#   pois um snapd não-pronto não deve abortar todo o provisionamento.
if [ "$ARCH" = "amd64" ]; then
  apt-get install -y -qq google-chrome-stable
  rm -f /etc/apt/sources.list.d/google-chrome.sources
elif [ "$DISTRO_ID" = "ubuntu" ]; then
  apt-get install -y -qq chromium-browser || \
    echo "⚠ chromium-browser (snap) falhou — instale depois com: sudo snap install chromium"
else
  apt-get install -y -qq chromium
fi

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
