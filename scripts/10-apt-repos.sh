#!/usr/bin/env bash
# 10-apt-repos.sh — base tools, timezone, external apt repos (Chrome, Docker, gh).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# ── Força dpkg não-interativo ───────────────────────────
fetch_asset apt/99force-conf /etc/apt/apt.conf.d/99force-conf

# ── Pre-seed grub-pc para evitar prompt interativo no upgrade ──
# bento/debian-13 entrega a imagem sem grub-pc/install_devices definido em
# debconf. Quando `apt-get upgrade` puxa um grub-pc novo (ex.: 2.12-9+deb13u1),
# o postinst chama `grub-install` em modo dialog; sob DEBIAN_FRONTEND=noninteractive
# isso aborta com "You must correct your GRUB install devices before proceeding"
# e quebra todo o provisionamento. Detectamos o disco-raiz e fazemos o seed
# antes do upgrade.
ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null || true)
ROOT_DISK=""
if [[ -n "$ROOT_SRC" ]]; then
  PKNAME=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | awk 'NF{print; exit}' || true)
  [[ -n "$PKNAME" ]] && ROOT_DISK="/dev/$PKNAME"
fi
ROOT_DISK="${ROOT_DISK:-/dev/sda}"
echo "grub-pc grub-pc/install_devices multiselect $ROOT_DISK" | debconf-set-selections
echo "grub-pc grub-pc/install_devices_empty boolean false"   | debconf-set-selections

echo "══════════════════════════════════════════"
echo "  Atualizando sistema base"
echo "══════════════════════════════════════════"

# ── Ferramentas essenciais (Debian minimal não inclui curl) ─
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl ca-certificates gnupg
install -m 0755 -d /etc/apt/keyrings

# ── Timezone (sem depender de timedatectl/dbus) ─────────
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
echo "America/Sao_Paulo" > /etc/timezone

# ── Repos externos (Chrome + Docker + GitHub CLI) ───────
echo ">> Configurando repositórios externos..."

# O Google Chrome só publica build Linux para amd64. Em arm64 (Apple Silicon /
# UTM) usamos o chromium do Debian (instalado em 20-packages.sh), então o repo
# do Chrome só é adicionado em amd64 — em arm64 ele só geraria ruído de
# "doesn't support architecture" no apt update.
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/google-chrome.gpg
  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' \
    > /etc/apt/sources.list.d/google-chrome.list
fi

# Identidade da distro (compartilhada pelos blocos Docker e PHP abaixo).
# DISTRO_ID = debian | ubuntu; CODENAME = bookworm/trixie/noble/...
# shellcheck source=/dev/null
DISTRO_ID=$(. /etc/os-release && echo "$ID")
# shellcheck source=/dev/null
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
ARCH=$(dpkg --print-architecture)

# Docker: repo específico da distro (linux/debian ou linux/ubuntu). Se o repo
# não tiver o codename atual (ex.: Debian Trixie ainda sem repo Docker), cai
# para um codename LTS estável da mesma família.
DOCKER_BASE="https://download.docker.com/linux/${DISTRO_ID}"
curl -fsSL "${DOCKER_BASE}/gpg" | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
DOCKER_CODENAME="$CODENAME"
if ! curl -fsSL "${DOCKER_BASE}/dists/${DOCKER_CODENAME}/Release" &>/dev/null; then
  if [ "$DISTRO_ID" = "ubuntu" ]; then DOCKER_CODENAME="jammy"; else DOCKER_CODENAME="bookworm"; fi
fi
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE} ${DOCKER_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/githubcli.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

# Visual Studio Code (Microsoft) — `code` package installed in 20-packages.sh,
# configured in 66-vscode.sh.
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/microsoft.gpg
chmod a+r /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  > /etc/apt/sources.list.d/vscode.list

# ── PHP 8.4 onde a distro não o traz nativo ─────────────
# PHP 8.4 é requisito do projeto. Fontes por distro (os pacotes php8.4-* são
# instalados em 20-packages.sh):
#   • Debian 13 Trixie: nativo (nada a fazer).
#   • Debian 12/11 (Bookworm/Bullseye): repo Sury (deb.sury.org) — publica
#     php8.4-* também em arm64. Usamos o PACOTE de keyring oficial
#     (debsuryorg-archive-keyring.deb) em vez do apt.gpg cru, evitando os erros
#     de BADSIG / "Splitting up InRelease ... failed" em algumas versões do apt.
#   • Ubuntu (24.04 só traz 8.3): PPA ondrej/php — mesmo mantenedor do Sury,
#     com builds arm64. add-apt-repository resolve a chave automaticamente.
case "$DISTRO_ID" in
  debian)
    case "$CODENAME" in
      bullseye|bookworm)
        curl -fsSL https://packages.sury.org/debsuryorg-archive-keyring.deb \
          -o /tmp/debsuryorg-archive-keyring.deb
        dpkg -i /tmp/debsuryorg-archive-keyring.deb
        rm -f /tmp/debsuryorg-archive-keyring.deb
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${CODENAME} main" \
          > /etc/apt/sources.list.d/sury-php.list
        ;;
    esac
    ;;
  ubuntu)
    apt-get install -y -qq software-properties-common
    # Garante o componente 'universe' — onde vivem xfce4, tilix, sassc, papirus,
    # etc. (a imagem cloud do Ubuntu costuma já habilitar, mas não custa).
    add-apt-repository -y universe
    add-apt-repository -y ppa:ondrej/php
    ;;
esac

# ── Único update com todos os repos prontos ─────────────
apt-get update -qq
