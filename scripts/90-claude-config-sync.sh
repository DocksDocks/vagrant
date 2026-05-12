#!/usr/bin/env bash
# 90-claude-config-sync.sh — sync AI agent configs from DocksDocks/public via sync.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo ">> Syncing Claude/Codex config from SSOT via sync.sh..."
su - vagrant <<'SYNC_AGENT_CONFIG'
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  . "$HOME/.nvm/nvm.sh"
fi
WORKDIR="$HOME/docksdocks-public"
rm -rf "$WORKDIR"
git clone --depth 1 https://github.com/DocksDocks/public.git "$WORKDIR"
cd "$WORKDIR"
bash sync.sh
cd /
rm -rf "$WORKDIR"
SYNC_AGENT_CONFIG
