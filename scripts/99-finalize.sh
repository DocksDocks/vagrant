#!/usr/bin/env bash
# 99-finalize.sh — print provisioning summary + ssh pubkey, nag about any
# remaining user action (git identity, gh auth), reboot on first provision.
set -euo pipefail

echo ""
echo "══════════════════════════════════════════"
echo "  Provisionamento concluído!"
echo "══════════════════════════════════════════"
echo "  git        : $(git --version)"
echo "  gh         : $(gh --version | head -1)"
echo "  python     : $(python3 --version)"
echo "  php        : $(php --version | head -1)"
echo "  composer   : $(composer --version 2>&1 | head -1)"
echo "  docker     : $(docker --version)"
echo "  compose    : $(docker compose version)"
echo "  shellcheck : $(shellcheck --version | grep version:)"
echo "  jq         : $(jq --version)"
echo "  yq         : $(yq --version)"
echo "  ripgrep    : $(rg --version | head -1)"
echo "  tilix      : tilix $(dpkg-query -f '${Version}' -W tilix 2>/dev/null || echo 'unknown')"
echo "  bat        : $(batcat --version | head -1)"
echo "  fzf        : $(fzf --version)"
echo "  htop       : $(htop --version | head -1)"
echo "  btop       : $(btop --version | head -1)"
echo "  spf        : $(spf --version 2>&1 | head -1)"
echo "  lazygit    : $(lazygit --version | head -1)"
# shellcheck disable=SC2016  # $(...) intentionally evaluated inside vagrant's shell after nvm sources
su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && echo "  node       : $(node --version)" && echo "  npm        : $(npm --version)" && echo "  pnpm       : $(pnpm --version)" && echo "  codex      : $(codex --version)"'
echo "══════════════════════════════════════════"
echo ""
echo "══════════════════════════════════════════"
echo "  SSH Public Key (copie para GitHub/etc):"
echo "══════════════════════════════════════════"
cat /home/vagrant/.ssh/id_ed25519.pub
echo ""
echo "══════════════════════════════════════════"

# ── Show what still needs user action (auth + git identity) ────────────
# Re-provision is idempotent so we re-check status every run.
git_name="$(su - vagrant -c 'git config --global --get user.name  2>/dev/null' || true)"
git_mail="$(su - vagrant -c 'git config --global --get user.email 2>/dev/null' || true)"
gh_status="$(su - vagrant -c 'gh auth status -h github.com 2>&1' || true)"

needs_action=0
if [ "$git_name" = "Your Name" ] || [ -z "$git_name" ] || \
   [ "$git_mail" = "you@example.com" ] || [ -z "$git_mail" ]; then
  needs_action=1
fi
if ! printf '%s' "$gh_status" | grep -q 'Logged in to github.com'; then
  needs_action=1
fi

if [ "$needs_action" -eq 1 ]; then
  echo ""
  echo "  ⚠ Ainda precisa configurar:"
  if [ "$git_name" = "Your Name" ] || [ -z "$git_name" ] || \
     [ "$git_mail" = "you@example.com" ] || [ -z "$git_mail" ]; then
    echo "    git config --global user.name  \"Seu Nome\""
    echo "    git config --global user.email \"seu@email.com\""
  fi
  if ! printf '%s' "$gh_status" | grep -q 'Logged in to github.com'; then
    echo "    gh auth login"
  fi
  echo "══════════════════════════════════════════"
else
  echo ""
  echo "  ✓ git: $git_name <$git_mail>"
  echo "  ✓ gh : $(printf '%s' "$gh_status" | grep -m1 'Logged in' | sed 's/^[[:space:]]*//')"
  echo "══════════════════════════════════════════"
fi

# ── Reboot para ativar graphical.target + autologin (só no primeiro provisionamento) ────
if [ ! -f /var/lib/vagrant-provisioned ]; then
  touch /var/lib/vagrant-provisioned
  echo ">> Reiniciando para ativar desktop com autologin..."
  nohup bash -c 'sleep 5 && reboot' &>/dev/null &
fi
