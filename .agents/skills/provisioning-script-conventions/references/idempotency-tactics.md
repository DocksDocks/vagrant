# Idempotency Tactics for Provisioning Scripts

<constraint>
Scripts MUST be safe to re-run via `vagrant provision`. Never write code that fails or produces duplicate state on a second run. Use one of the three guards below.
</constraint>

## Three Idempotency Patterns

### 1. Command-existence guard + FORCE_REINSTALL bypass

Used for expensive installs (Guest Additions ISO build, Nerd Font download, nvm+Node).

```bash
if [[ "${FORCE_REINSTALL:-0}" != "1" ]] && command -v VBoxClient >/dev/null 2>&1; then
  echo ">> VirtualBox Guest Additions already installed — skipping (set FORCE_REINSTALL=1 to redo)."
  exit 0
fi
```

Source: `scripts/30-guest-additions.sh:12-16`

File-existence variant (same pattern):
```bash
if [[ "$FORCE" != "1" ]] && [ -f "${FONT_DIR}/JetBrainsMonoNerdFont-Regular.ttf" ]; then
  echo ">> JetBrainsMono Nerd Font already installed — skipping."
fi
if [[ "$FORCE" != "1" ]] && [ -x /usr/local/bin/spf ]; then
  echo ">> superfile already installed — skipping."
fi
```

Source: `scripts/65-superfile-fonts.sh:15-16`, `scripts/65-superfile-fonts.sh:32-33`

Scripts that support FORCE_REINSTALL: 30-guest-additions.sh, 65-superfile-fonts.sh, 70-nodejs-claude.sh.

### 2. grep-q marker guard for bashrc appends

Used for any block appended to `~/.bashrc`.

```bash
if ! grep -qF '85-secrets-env.sh' "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_SECRETS'

# Source ~/.config/secrets.env if present (managed by 85-secrets-env.sh)
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"
BASHRC_SECRETS
fi
```

Source: `scripts/85-secrets-env.sh:50-55`

The marker string MUST be unique per script (use the script's filename in a comment). Scripts using this pattern: `scripts/80-git-ssh.sh:24-30`, `scripts/85-secrets-env.sh:50`, `scripts/60-apps-tilix-mousepad.sh:74`, `scripts/70-nodejs-claude.sh:45`.

### 3. File-existence guard for one-time scaffolding

Used for files that should be created once and never clobbered (e.g. the secrets placeholder).

```bash
if [[ ! -e "$SECRETS_FILE" ]]; then
  install -d -m 0700 "$USER_HOME/.config"
  cat > "$SECRETS_FILE" <<'EOF'
# ...
EOF
  chmod 0600 "$SECRETS_FILE"
fi
```

Source: `scripts/85-secrets-env.sh:31-45`

Use `[[ ! -e FILE ]]` (not `-f`) to catch symlinks and directories with the same name.

## First-Provision Reboot Sentinel

The sentinel at `/var/lib/vagrant-provisioned` gates the reboot at the end of the provisioning chain:

```bash
if [ ! -f /var/lib/vagrant-provisioned ]; then
  touch /var/lib/vagrant-provisioned
  echo ">> Reiniciando para ativar desktop com autologin..."
  nohup bash -c 'sleep 5 && reboot' &>/dev/null &
fi
```

Source: `scripts/99-finalize.sh:73-77`

Location in `/var/lib/` (not `/tmp/`) ensures it survives reboots but is absent after `vagrant destroy -f && vagrant up`, correctly re-triggering the first-provision reboot on a fresh VM.

## Pattern Decision Table

| Situation | Pattern | Example script |
|---|---|---|
| Expensive install (network/build) | command-v / file-exists + FORCE_REINSTALL | 30, 65, 70 |
| ~/.bashrc append | grep-q marker guard | 60, 70, 80, 85 |
| One-time config file scaffolding | file-exists (`! -e`) guard | 85 |
| Reboot gate | file-exists in `/var/lib/` | 99-finalize |
| Asset deploy (fetch_asset) | Inherently idempotent (overwrites) | all |
| apt install | Inherently idempotent (already-installed = fast) | 10, 20 |

## FORCE_REINSTALL env passthrough

The Vagrantfile forwards `FORCE_REINSTALL` to every script via the `env` hash:

```ruby
env = {
  "FORCE_REINSTALL" => ENV["FORCE_REINSTALL"],
}.compact
```

Source: `Vagrantfile:120-128`. `.compact` drops nil values so the var is absent (not empty string) when unset. Scripts check `${FORCE_REINSTALL:-0}` to treat absent as "0".

Usage: `FORCE_REINSTALL=1 vagrant provision` — bypasses all three expensive-install guards in one invocation.

## Gotchas

**Using `exit 0` in a guard inside a sourced file**: `exit` terminates the entire shell. Use `return 0` if the guard is in a function; use `exit 0` only at the top level of a non-sourced script. The skip guards above use `exit 0` correctly in top-level scripts.

**`apt install` idempotency assumed but not guaranteed on first run**: `apt-get install -y` is idempotent for already-installed packages but NOT if the package list is stale. `scripts/10-apt-repos.sh` runs first and updates the list; if it ever runs out of order, subsequent apt calls may fail with "Unable to locate package". The `SCRIPTS` array order is the single source of truth.

**Vagrant provision timing**: `vagrant provision` re-runs ALL scripts in the SCRIPTS array. To re-run only one script, use `vagrant provision --provision-with 50-vboxclient-supervisor`. Source: `plans/0002-split-vagrantfile.md:141`.
