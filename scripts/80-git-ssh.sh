#!/usr/bin/env bash
# 80-git-ssh.sh — git-pull-all + SSH key + bashrc aliases + git defaults.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# ── git-pull-all (bulk fetch + ff-only pull) ────────────
# Walks a directory tree and updates every repo under it. On PATH as
# git-pull-all, so `git pull-all` dispatches to it too. fetch_asset lands it
# 0644; flip the exec bit so it's runnable.
echo ">> Instalando git-pull-all..."
fetch_asset bin/git-pull-all /usr/local/bin/git-pull-all
chmod 0755 /usr/local/bin/git-pull-all

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
# Set defaults only — `vagrant provision` may run after the user has
# configured real identity, and unconditionally setting these clobbers it.
su - vagrant -c 'git config --global init.defaultBranch main'
su - vagrant -c 'git config --global --get user.name  >/dev/null 2>&1 || git config --global user.name  "Your Name"'
su - vagrant -c 'git config --global --get user.email >/dev/null 2>&1 || git config --global user.email "you@example.com"'
