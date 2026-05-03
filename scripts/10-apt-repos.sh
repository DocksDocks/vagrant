#!/usr/bin/env bash
# 10-apt-repos.sh — base tools, timezone, external apt repos (Chrome, Docker, gh).
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

curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/google-chrome.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' \
  > /etc/apt/sources.list.d/google-chrome.list

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

# ── Único update com todos os repos prontos ─────────────
apt-get update -qq
