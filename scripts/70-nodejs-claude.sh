#!/usr/bin/env bash
# 70-nodejs-claude.sh — nvm + Node LTS + pnpm + Claude Code.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Node.js LTS (via nvm) + pnpm + Claude Code ──────────
echo ">> Instalando nvm + node LTS + pnpm + claude code..."
su - vagrant -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && npm install -g pnpm'
su - vagrant -c 'curl -fsSL https://claude.ai/install.sh | bash' || echo "⚠ Claude Code install falhou (pode ser falta de RAM). Tente instalar manualmente depois: curl -fsSL https://claude.ai/install.sh | bash"
# shellcheck disable=SC2016  # intentional: $HOME/$PATH stay unexpanded inside ~/.bashrc
su - vagrant -c 'grep -q "\.local/bin" ~/.bashrc 2>/dev/null || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc'
