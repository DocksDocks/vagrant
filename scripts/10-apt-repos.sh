#!/usr/bin/env bash
# 10-apt-repos.sh — base tools, timezone, external apt repos (Chrome, Docker, gh).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" ]]; then
    install -D -m 0644 "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}

# ── Força dpkg não-interativo ───────────────────────────
fetch_asset apt/99force-conf /etc/apt/apt.conf.d/99force-conf

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
