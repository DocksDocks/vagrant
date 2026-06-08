#!/usr/bin/env bash
# 85-secrets-env.sh — scaffold ~/.config/secrets.env + source from ~/.bashrc.
#
# Convention: anything sensitive (API keys, OAuth tokens, JWTs) goes in a
# 0600 file under ~/.config, not in ~/.bashrc itself. Reasons:
#   - ~/.bashrc is sourced by every interactive shell; secrets there leak
#     to every subprocess that reads $BASH_ENV or `cat ~/.bashrc`.
#   - Backup tooling (this repo's snapshot tarball, dotfile sync) tends to
#     pull in ~/.bashrc verbatim; a secrets dropoff under ~/.config can be
#     selectively excluded from backups.
#   - Tools that write to ~/.bashrc (e.g. n8n-workflows/scripts/setup-n8n-mcp.sh)
#     can target ~/.config/secrets.env once it exists, keeping the rc file
#     limited to shell config.
#
# This script:
#   1. Creates an empty placeholder ~/.config/secrets.env (mode 0600, owner
#      vagrant) with a comment header pointing to this convention.
#   2. Adds an idempotent guarded-source line to ~/.bashrc.
#
# No secrets are written here — only the scaffolding. The placeholder file
# stays empty until a downstream tool or the user populates it.
set -euo pipefail

USER_HOME=/home/vagrant
SECRETS_FILE="$USER_HOME/.config/secrets.env"
BASHRC="$USER_HOME/.bashrc"

# 1. Placeholder file (don't clobber an existing one). This script runs AFTER
# 55-permissions.sh, so it can't lean on that sweep to fix ownership — it must
# create the file owned by vagrant itself. A root-owned 0600 secrets.env would
# be unreadable by vagrant, so the `[ -r … ]` guard in ~/.bashrc (step 2) would
# silently skip it and the secrets would never load. Own it to vagrant + 0600.
if [[ ! -e "$SECRETS_FILE" ]]; then
  install -d -o vagrant -g vagrant -m 0700 "$USER_HOME/.config"
  cat > "$SECRETS_FILE" <<'EOF'
# secrets.env — sourced from ~/.bashrc (managed by 85-secrets-env.sh).
#
# Drop POSIX-shell `export` lines for sensitive values here instead of
# polluting ~/.bashrc. Mode 0600, owner vagrant.
#
#   export GITHUB_TOKEN="ghp_..."
#   export OPENAI_API_KEY="sk-..."
#
# Keep this file out of any dotfile sync or backup that targets ~/.bashrc.
EOF
  chown vagrant:vagrant "$SECRETS_FILE"
  chmod 0600 "$SECRETS_FILE"
fi

# 2. Idempotent source-line append to ~/.bashrc. The marker is the script
# filename in the comment — uniquely identifies our block on re-provision.
# Appending with `cat >>` preserves ~/.bashrc's existing owner (vagrant).
if ! grep -qF '85-secrets-env.sh' "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_SECRETS'

# Source ~/.config/secrets.env if present (managed by 85-secrets-env.sh)
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"
BASHRC_SECRETS
fi
