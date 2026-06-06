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

curl -fsSL https://download.docker.com/linux/debian/gpg | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
# shellcheck source=/dev/null
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
# Docker pode não ter repo para trixie ainda — fallback para bookworm
if ! curl -fsSL "https://download.docker.com/linux/debian/dists/${CODENAME}/Release" &>/dev/null; then
  CODENAME="bookworm"
fi
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" \
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

# ── PHP 8.4 via Sury (deb.sury.org) onde o Debian não o traz nativo ──
# O Debian 13 (Trixie, base do box amd64) já empacota PHP 8.4. O Debian 12
# (Bookworm, base do box arm64/UTM) só traz 8.2, e PHP 8.4 é requisito do
# projeto — então adicionamos o repo do Ondřej Surý, que publica 8.4 para
# Bookworm em amd64 E arm64, incluindo as extensões que usamos (cli, curl,
# mbstring, xml, zip, bcmath, intl). Os pacotes php8.4-* são instalados em
# 20-packages.sh. Só adicionamos o repo quando o codename não é trixie+ (i.e.,
# bookworm/bullseye), onde o 8.4 nativo não existe.
#
# Usamos o PACOTE de keyring oficial (debsuryorg-archive-keyring.deb) em vez de
# baixar apt.gpg direto: o pacote instala o keyring no formato correto em
# /usr/share/keyrings, evitando os erros recorrentes de BADSIG / "Splitting up
# InRelease ... failed" que o apt.gpg cru provoca em algumas versões do apt.
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
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

# ── Único update com todos os repos prontos ─────────────
apt-get update -qq
