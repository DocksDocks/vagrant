---
name: secrets-env-convention
description: Use when handling secrets in the guest - storing API keys, OAuth tokens, JWTs, GITHUB_TOKEN, OPENAI_API_KEY in ~/.config/secrets.env (mode 0600, owner vagrant, NOT in ~/.bashrc), sourcing secrets from ~/.bashrc behind a [ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env" guard with the unique '85-secrets-env.sh' marker for grep-q idempotency, scaffolding the placeholder file via install -d -m 0700 ~/.config + heredoc + chmod 0600, or instructing a downstream tool to write secrets to ~/.config/secrets.env instead of polluting ~/.bashrc. Not for systemwide /etc/environment, Docker secrets, ssh keys (id_ed25519 has its own 0600 path under ~/.ssh/), or VBox clipboard supervision.
user-invocable: false
metadata:
  pattern: tool-wrapper
  source_files:
    - "scripts/85-secrets-env.sh"
  updated: "2026-05-03"
---

# Secrets-Env Convention

<constraint>
Secrets MUST go in `~/.config/secrets.env` (mode 0600), NOT in `~/.bashrc`. Anything in `~/.bashrc` is visible to every subprocess, backup tooling, and dotfile sync. Source: `scripts/85-secrets-env.sh:3-13`.
</constraint>

<constraint>
The `~/.bashrc` source line MUST use the idempotency guard with the `85-secrets-env.sh` marker. Without it, each `vagrant provision` run appends a duplicate source block. Source: `scripts/85-secrets-env.sh:47-55`.
</constraint>

## When to Use

- Adding a new API key or token to the VM (GITHUB_TOKEN, OPENAI_API_KEY, etc.).
- Writing a downstream provisioning script that needs to store credentials.
- Instructing a user where to put secrets in this VM.
- Debugging why a secret is not available in shell (source guard issue).
- Adding a new secrets-writing script that must check for the existing file.

## Core Patterns

### Placeholder scaffolding (one-time, never clobbers)

```bash
USER_HOME=/home/vagrant
SECRETS_FILE="$USER_HOME/.config/secrets.env"
BASHRC="$USER_HOME/.bashrc"

if [[ ! -e "$SECRETS_FILE" ]]; then
  install -d -m 0700 "$USER_HOME/.config"
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
  chmod 0600 "$SECRETS_FILE"
fi
```

Source: `scripts/85-secrets-env.sh:24-45`. `[[ ! -e "$SECRETS_FILE" ]]` uses `-e` (not `-f`) to catch symlinks and directories with the same name. `install -d -m 0700` creates `~/.config` with restrictive permissions.

### Idempotent bashrc source line

```bash
if ! grep -qF '85-secrets-env.sh' "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_SECRETS'

# Source ~/.config/secrets.env if present (managed by 85-secrets-env.sh)
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"
BASHRC_SECRETS
fi
```

Source: `scripts/85-secrets-env.sh:50-55`. The `[ -r FILE ] && . FILE` pattern silently does nothing if the file doesn't exist or isn't readable — safe for new VMs where the file is empty and for cases where the file is intentionally absent.

### Downstream tool writing secrets

Any tool or script that needs to write a secret to this VM should:

1. Check that `~/.config/secrets.env` exists (it will if `85-secrets-env.sh` ran).
2. Append `export KEY="value"` to the file.
3. NOT append to `~/.bashrc`.

Example:
```bash
SECRETS_FILE="$HOME/.config/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
  echo 'export GITHUB_TOKEN="ghp_..."' >> "$SECRETS_FILE"
else
  echo "WARNING: $SECRETS_FILE not found — run 85-secrets-env.sh first" >&2
fi
```

## Key Decisions

- **Mode 0600 set at creation time**: ownership is corrected by `scripts/95-permissions.sh` (the chown sweep), but mode must be 0600 from the moment the file exists — regardless of when 95-permissions.sh runs. Source: `scripts/85-secrets-env.sh:29-30`.
- **`[ -r FILE ] && . FILE` not `source FILE`**: `source` (bash builtin) is not POSIX; the dot-source with `-r` guard works in any POSIX shell and handles a missing file gracefully.
- **`~/.config/` at 0700**: the directory itself is restricted so other users cannot enumerate its contents even if they cannot read individual files.
- **Never sourced at system level**: `~/.config/secrets.env` is only sourced by `~/.bashrc` — not by `/etc/environment`, `/etc/profile`, or any system-level file. Secrets are vagrant-user-scoped only.

## Why Not ~/.bashrc Directly

| Problem | Detail |
|---|---|
| Subprocess leakage | Every subprocess that reads `$BASH_ENV` or `cat ~/.bashrc` sees the secrets |
| Backup tooling | dotfile syncs and snapshot tarballs pull in `~/.bashrc` verbatim |
| `vagrant provision` duplication | Each re-provision appends without a guard |
| Diff noise | Every new secret pollutes `~/.bashrc` git diffs if it's tracked |

Source: `scripts/85-secrets-env.sh:3-13` (comment block).

## Gotchas

**Secret not available in a new shell**: the `[ -r FILE ] && . FILE` line is in `~/.bashrc`, which is only sourced for interactive non-login shells. Login shells source `~/.bash_profile` (which on Debian typically sources `~/.bashrc` via `if [ -f ~/.bashrc ]; then . ~/.bashrc; fi`). If a secret is missing in a login shell, check `~/.bash_profile` sources `~/.bashrc`.

**mode 0600 lost after `vagrant provision`**: `scripts/95-permissions.sh` runs `chown -R vagrant:vagrant /home/vagrant` but does NOT change modes. Mode 0600 set during scaffolding is preserved. However, if a downstream script writes to the file with a umask that sets 0644, run `chmod 0600 ~/.config/secrets.env` to fix.

**Multiple downstream tools appending the same key**: `~/.config/secrets.env` has no deduplication — if two scripts append `export GITHUB_TOKEN=...`, both values are set in sequence and the last one wins (bash source executes top-to-bottom). Keep one canonical source of each key.

**Empty placeholder is normal**: `85-secrets-env.sh` writes a comment-only placeholder. An empty `secrets.env` is the expected state of a freshly provisioned VM before the user or a downstream tool populates it.
