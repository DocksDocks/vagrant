#!/usr/bin/env bash
# 90-claude-config-sync.sh — sync .claude config from DocksDocks/public SSOT via sync.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo ">> Syncing .claude config from SSOT via sync.sh..."
su - vagrant -c '
  set -e
  rm -rf /tmp/docksdocks-public
  git clone --depth 1 https://github.com/DocksDocks/public.git /tmp/docksdocks-public
  cd /tmp/docksdocks-public
  bash sync.sh
  cd /
  rm -rf /tmp/docksdocks-public
'
