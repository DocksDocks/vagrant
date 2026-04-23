#!/usr/bin/env bash
# 65-superfile-fonts.sh — JetBrainsMono Nerd Font + superfile (spf) TUI file manager.
#
# Idempotent: skips each component if already present. Set FORCE_REINSTALL=1 to
# redo everything. Both installs hit GitHub releases, so skipping on re-provision
# avoids repeated network calls.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

FORCE="${FORCE_REINSTALL:-0}"

# ── JetBrainsMono Nerd Font (system-wide) ───────────────
# Needed for superfile's glyphs/icons to render in the terminal.
FONT_DIR="/usr/local/share/fonts/JetBrainsMonoNerdFont"
if [[ "$FORCE" != "1" ]] && [ -f "${FONT_DIR}/JetBrainsMonoNerdFont-Regular.ttf" ]; then
  echo ">> JetBrainsMono Nerd Font already installed — skipping."
else
  echo ">> Instalando JetBrainsMono Nerd Font..."
  rm -rf "$FONT_DIR"
  mkdir -p "$FONT_DIR"
  curl -fsSL --retry 4 --retry-delay 2 \
    -o /tmp/JetBrainsMono.tar.xz \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  tar -xJf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"
  rm -f /tmp/JetBrainsMono.tar.xz
  fc-cache -f "$FONT_DIR"
fi

# ── superfile (spf) ─────────────────────────────────────
# GitHub release pattern: superfile-linux-v${VERSION}-amd64.tar.gz.
# Same curl+tar idiom used for lazygit in 80-git-ssh-lazygit.sh.
if [[ "$FORCE" != "1" ]] && [ -x /usr/local/bin/spf ]; then
  echo ">> superfile already installed — skipping."
else
  echo ">> Instalando superfile..."
  SPF_VERSION=$(curl -fsSL --retry 4 --retry-delay 2 \
    "https://api.github.com/repos/yorukot/superfile/releases/latest" \
    | jq -r '.tag_name' | sed 's/^v//')
  SPF_DIRNAME="superfile-linux-v${SPF_VERSION}-amd64"
  curl -fsSL --retry 4 --retry-delay 2 \
    -o /tmp/superfile.tar.gz \
    "https://github.com/yorukot/superfile/releases/download/v${SPF_VERSION}/${SPF_DIRNAME}.tar.gz"
  # Tarball layout: ./dist/${SPF_DIRNAME}/spf
  tar -xzf /tmp/superfile.tar.gz -C /tmp
  install -m 0755 "/tmp/dist/${SPF_DIRNAME}/spf" /usr/local/bin/spf
  rm -rf /tmp/superfile.tar.gz /tmp/dist
fi
