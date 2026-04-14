#!/usr/bin/env bash
# 80-git-ssh-lazygit.sh — Lazygit + SSH key + bashrc aliases + git defaults.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Lazygit (terminal Git UI) ───────────────────────────
echo ">> Instalando lazygit..."
LAZYGIT_VERSION=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" | \
  tar -xz -C /usr/local/bin lazygit

# ── SSH Key + alias + ~/projects ────────────────────────
echo ">> Configurando SSH key, alias e diretório de projetos..."
su - vagrant -c 'mkdir -p ~/projects'
su - vagrant -c 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "vagrant@dev-box" -f ~/.ssh/id_ed25519 -N ""'
su - vagrant -c 'grep -q "alias pf=" ~/.bashrc 2>/dev/null || echo "alias pf=\"cd ~/projects\"" >> ~/.bashrc'
su - vagrant -c 'grep -q "alias fd=" ~/.bashrc 2>/dev/null || echo "alias fd=fdfind" >> ~/.bashrc'
su - vagrant -c 'grep -q "alias bat=" ~/.bashrc 2>/dev/null || echo "alias bat=batcat" >> ~/.bashrc'
# shellcheck disable=SC2016  # intentional: $(...) stays unexpanded inside ~/.bashrc
su - vagrant -c 'grep -q "direnv hook" ~/.bashrc 2>/dev/null || echo "eval \"\$(direnv hook bash)\"" >> ~/.bashrc'
# shellcheck disable=SC2016  # intentional: $(id -u) stays unexpanded inside ~/.bashrc
su - vagrant -c 'grep -q "XDG_RUNTIME_DIR" ~/.bashrc 2>/dev/null || echo "export XDG_RUNTIME_DIR=/run/user/\$(id -u)" >> ~/.bashrc'

# ── Git config ──────────────────────────────────────────
su - vagrant -c 'git config --global init.defaultBranch main'
su - vagrant -c 'git config --global user.name "Your Name"'
su - vagrant -c 'git config --global user.email "you@example.com"'
