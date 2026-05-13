---
name: provisioning-script-conventions
description: Use when adding or modifying numbered provisioning scripts under scripts/ (10-apt-repos.sh through 99-finalize.sh), sourcing $VAGRANT_LIB_PATH / scripts/_lib.sh, deploying assets with fetch_asset REL DEST, respecting SCRIPTS_REPO / SCRIPTS_REF / VAGRANT_SCRIPTS_DIR / FORCE_REINSTALL, adding Vagrantfile SCRIPTS entries, or running downloaded installers with SHA-384 verification. Not for VirtualBox VMSVGA gotchas, XFCE desktop config, Ruby host detection, secrets.env, or ADRs under plans/.
user-invocable: false
metadata:
  pattern: tool-wrapper
  source_files:
    - "scripts/_lib.sh"
    - "scripts/10-apt-repos.sh"
    - "scripts/20-packages.sh"
    - "scripts/30-guest-additions.sh"
    - "scripts/40-xfce-base.sh"
    - "scripts/41-xfce-theme.sh"
    - "scripts/50-vboxclient-supervisor.sh"
    - "scripts/51-vbox-autoresize.sh"
    - "scripts/60-apps-tilix-mousepad.sh"
    - "scripts/65-superfile-fonts.sh"
    - "scripts/70-nodejs-claude.sh"
    - "scripts/80-git-ssh-lazygit.sh"
    - "scripts/55-permissions.sh"
    - "scripts/85-secrets-env.sh"
    - "scripts/90-claude-config-sync.sh"
    - "scripts/99-finalize.sh"
    - "plans/0002-split-vagrantfile.md"
    - "README.md"
  updated: "2026-05-13"
---

# Provisioning Script Conventions

<constraint>
Every numbered script MUST open with `set -euo pipefail` + `export DEBIAN_FRONTEND=noninteractive`. Omitting either means a failing apt/curl/dconf call silently continues and produces a partially-configured VM.
</constraint>

<constraint>
Never run a downloaded installer as root without SHA-384 verification against the publisher's canonical hash endpoint. See references/installer-trust-verification.md for the Composer pattern.
</constraint>

<constraint>
Never append to ~/.bashrc without a `grep -q` marker guard. Each re-provision run would duplicate the block.
</constraint>

<constraint>
Never call `systemctl --user enable` during provisioning — no active user manager exists. Use WantedBy symlinks directly (see scripts/50-vboxclient-supervisor.sh:34-41).
</constraint>

## When to Use

- Adding a new script to the `SCRIPTS` array in Vagrantfile.
- Deciding a numbered slot for a new script (gaps: 25, 35, 45, 75, 95 are free).
- Sourcing `_lib.sh` and calling `fetch_asset` to deploy an asset.
- Writing the mandatory 4-line preamble for any numbered script.
- Adding an idempotent append to `~/.bashrc`.
- Running a curl-fetched installer as root (Composer pattern).
- Understanding why `55-permissions.sh` chown-sweeps `/home/vagrant` between system-config and user-install phases.

## Core Patterns

### Mandatory preamble (every numbered script)

```bash
#!/usr/bin/env bash
# NN-name.sh — one-line description
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"
```

Source: `scripts/10-apt-repos.sh:1-10`, `scripts/40-xfce-base.sh:1-10`, pattern in all 14 numbered scripts.

The default-value guards (`: "${VAR:=default}"`) allow standalone execution (`bash scripts/41-xfce-theme.sh`) without the Vagrantfile env while still inheriting Vagrantfile-supplied values when provisioned.

### fetch_asset — deploy a static asset file

```bash
fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}
```

Source: `scripts/_lib.sh:21-31`

Usage: `fetch_asset xfwm4.xml /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`

See references/fetch-asset-helper.md for semantics.

### Script numbering convention

| Current slots | Free gaps (can insert here) |
|---|---|
| 10, 20, 30, 40, 41, 50, 51, 55, 60, 65, 70, 80, 85, 90, 99 | 25, 35, 45, 75, 95 |

Gaps are cosmetic — Vagrant executes in `SCRIPTS` array declaration order, not filename order. Source: `plans/0002-split-vagrantfile.md:44`.

### SCRIPTS array — add new scripts here, not anywhere else

```ruby
SCRIPTS = %w[
  10-apt-repos
  20-packages
  # ... add new entry in sorted position ...
  55-permissions
  # ... user-install scripts (60, 65, 70, 80, 85, 90) follow the sweep ...
  99-finalize
]
```

Source: `Vagrantfile:72-88`. Each entry must have a matching `scripts/NN-name.sh` file.

### `|| true` discipline

Use `|| true` ONLY on commands that can legitimately fail under `set -e`:

```bash
systemctl enable vboxadd-service 2>/dev/null || true   # unit may not exist yet
mount -o loop "$VBOX_ISO" /mnt 2>/dev/null || true     # may already be mounted
gtk-update-icon-cache -q -f "$ICON_DST" >/dev/null 2>&1 || true
```

Source: `scripts/30-guest-additions.sh:14`, `scripts/41-xfce-theme.sh:47`

Omit `|| true` from critical commands (curl fetches, apt installs, dconf compile) — failures there must abort provisioning visibly.

### Idempotent bashrc-append (grep-q marker guard)

```bash
if ! grep -qF '85-secrets-env.sh' "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_SECRETS'
# Source ~/.config/secrets.env if present (managed by 85-secrets-env.sh)
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"
BASHRC_SECRETS
fi
```

Source: `scripts/85-secrets-env.sh:50-55`. The marker string is the script filename in the comment — unique per script.

### 55-permissions.sh catch-all chown

```bash
chown -R vagrant:vagrant /home/vagrant
```

Source: `scripts/55-permissions.sh:16`. Scripts 40, 41, 50, 51 run as root and create root-owned directories under `/home/vagrant/{.config,.local,...}`; scripts 60+ run as the vagrant user (via `su - vagrant -c` / `runuser`) and need to write **into** those directories. The sweep runs **between** the two phases so user-phase writes don't EACCES. Do not add per-file chown calls — note the comment `# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.` used throughout. Why position 55 and not the trailing 95 it once occupied: a single late sweep crashed `vagrant up` because script 90 (`90-claude-config-sync.sh` → `sync.sh` rtk installer) tries to `mv ... ~/.local/bin/rtk` and hits EACCES before the chown can fire. Running the sweep before 60 fixes both that crash and the silent Claude Code install failure inside script 70.

### apt dpkg force-conf fragment

```
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
}
```

Source: `assets/apt/99force-conf:1-4`, installed by `scripts/10-apt-repos.sh:13`. Prevents `apt-get upgrade` from halting on "configuration file changed" prompts.

## Key Decisions

- **`set -euo pipefail` is non-negotiable**: any failing command aborts provisioning immediately with a visible error. Commands that can fail must use `|| true`. Source: `scripts/10-apt-repos.sh:3`.
- **VAGRANT_LIB_PATH fallback `/vagrant/scripts/_lib.sh`**: allows running a script standalone in local-dev mode without the Vagrantfile setting the env var. Source: `scripts/40-xfce-base.sh:9-10`.
- **`55-permissions.sh` is the single ownership sweep**: earlier scripts (40, 41, 50, 51) do not chown individual files, enabling them to run as root without tracking what they wrote; the sweep runs once at position 55, before the user-tool-install phase (60–90) consumes those dirs. Source: `scripts/55-permissions.sh:16`.
- **`FORCE_REINSTALL` bypass**: the three heavy scripts (30, 65, 70) check `${FORCE_REINSTALL:-0}` and skip if the tool is already installed; `FORCE_REINSTALL=1 vagrant provision` overrides all three. Source: `scripts/30-guest-additions.sh:12-16`.
- **Numbered gaps are intentional**: 25, 35, 45, 75, 95 are available for future scripts without renaming existing ones. Source: `plans/0002-split-vagrantfile.md:44`.

## Gotchas

**Missing `set -euo pipefail`**: a failing `apt-get install` or broken `curl` silently continues; the VM appears to provision but tools are missing or misconfigured. Every script must have this at line 3.

**Appending to ~/.bashrc without grep-q guard**: each `vagrant provision` run duplicates the block. Four scripts currently append to bashrc — all use the grep-q pattern. Source: `scripts/80-git-ssh-lazygit.sh:16-22`, `scripts/85-secrets-env.sh:50`, `scripts/60-apps-tilix-mousepad.sh:74`, `scripts/70-nodejs-claude.sh:55`.

**Missing `|| true` on `umount` / `systemctl enable`**: `set -e` aborts provisioning if the mount was never established or the unit doesn't exist yet. Source: `scripts/30-guest-additions.sh:48-50`.

**Hardcoding a SHA-384 hash for a rotating installer**: Composer releases a new hash on every version; hardcoding it causes the SHA check to fail on the next Composer release, aborting provisioning at `20-packages.sh`. Source: `scripts/20-packages.sh:32`.

**Running a script outside the Vagrantfile env** (missing `VAGRANT_LIB_PATH`): the `. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"` fallback handles this only if the repo is mounted at `/vagrant` (local-dev mode). In remote mode without the env var, `_lib.sh` is absent and `fetch_asset` is undefined.

**Adding a script file without updating `SCRIPTS` array**: Vagrant only executes provisioners declared in the array. A new `scripts/NN-name.sh` without a matching `SCRIPTS` entry is silently skipped. Source: `Vagrantfile:72-88`.

## References

- `references/fetch-asset-helper.md` — Read when: adding a new asset deploy call, troubleshooting local-dev vs remote mode mismatch, or understanding `install -D -m 0644` vs bare `cp`.
- `references/idempotency-tactics.md` — Read when: writing a new idempotency guard (command-v, grep-q, file-exists), deciding whether to add `FORCE_REINSTALL` support, or tracing the first-provision reboot sentinel.
- `references/installer-trust-verification.md` — Read when: running any curl-fetched installer as root; the Composer SHA-384 pattern is the template for all future installers.
