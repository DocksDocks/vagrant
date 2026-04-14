#!/usr/bin/env bash
# 70-nodejs-claude.sh — nvm + Node LTS + pnpm + Claude Code.
#
# Idempotency: on re-provision, skip each component that's already installed.
# Set FORCE_REINSTALL=1 to redo everything. The three installs here (nvm,
# node/pnpm, claude) each take tens of seconds and involve network calls, so
# skipping them on re-provision is the biggest single speedup in the script set.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

FORCE="${FORCE_REINSTALL:-0}"

# ── nvm ─────────────────────────────────────────────────
if [[ "$FORCE" != "1" ]] && [ -s /home/vagrant/.nvm/nvm.sh ]; then
  echo ">> nvm already installed — skipping (FORCE_REINSTALL=1 to redo)."
else
  echo ">> Instalando nvm..."
  su - vagrant -c 'curl -fsSL --retry 4 --retry-delay 2 https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
fi

# ── Node LTS + pnpm ─────────────────────────────────────
# nvm's `current` reports the active version for the shell; if a default LTS
# alias is set and pnpm is resolvable, we consider Node+pnpm installed.
if [[ "$FORCE" != "1" ]] && \
   su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh >/dev/null 2>&1 && \
     [ "$(nvm current 2>/dev/null)" != "none" ] && \
     command -v pnpm >/dev/null 2>&1' >/dev/null 2>&1; then
  echo ">> Node LTS + pnpm already installed — skipping."
else
  echo ">> Instalando node LTS + pnpm..."
  su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && npm install -g pnpm'
fi

# ── Claude Code ─────────────────────────────────────────
if [[ "$FORCE" != "1" ]] && [ -x /home/vagrant/.local/bin/claude ]; then
  echo ">> Claude Code already installed — skipping."
else
  echo ">> Instalando claude code..."
  su - vagrant -c 'curl -fsSL https://claude.ai/install.sh | bash' || \
    echo "⚠ Claude Code install falhou (pode ser falta de RAM). Tente instalar manualmente depois: curl -fsSL https://claude.ai/install.sh | bash"
fi

# PATH hint for ~/.local/bin (idempotent — only appends once)
# shellcheck disable=SC2016  # intentional: $HOME/$PATH stay unexpanded inside ~/.bashrc
su - vagrant -c 'grep -q "\.local/bin" ~/.bashrc 2>/dev/null || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc'
