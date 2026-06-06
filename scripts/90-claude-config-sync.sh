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
# Config sync is OPTIONAL — it must never abort the whole box provision. sync.sh
# can fail for reasons outside this repo: e.g. on Debian 12 Bookworm (the
# arm64/UTM box) a prebuilt tool built for a newer glibc won't run — `rtk`
# needs GLIBC_2.39 but Bookworm ships 2.36. Warn loudly and carry on so
# 99-finalize still runs and the desktop comes up; re-run sync.sh by hand later.
if ! bash sync.sh; then
  echo "⚠ sync.sh falhou — config dos agentes pode estar incompleta (seguindo)." >&2
  echo "  Em Bookworm/arm64, binários com glibc novo podem não rodar (ex.: rtk → GLIBC_2.39 vs 2.36 do Bookworm)." >&2
  echo "  Re-rode manualmente: git clone --depth 1 https://github.com/DocksDocks/public ~/dp && bash ~/dp/sync.sh" >&2
fi
cd /
rm -rf "$WORKDIR"
SYNC_AGENT_CONFIG
