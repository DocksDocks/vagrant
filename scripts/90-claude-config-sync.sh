#!/usr/bin/env bash
# 90-claude-config-sync.sh — sync .claude config from DocksDocks/public SSOT via sync.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo ">> Syncing .claude config from SSOT via sync.sh..."
su - vagrant -c '
  set -e
  WORKDIR="$HOME/docksdocks-public"
  rm -rf "$WORKDIR"
  git clone --depth 1 https://github.com/DocksDocks/public.git "$WORKDIR"
  cd "$WORKDIR"
  bash sync.sh
  cd /
  rm -rf "$WORKDIR"
'
