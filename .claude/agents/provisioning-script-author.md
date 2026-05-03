---
name: provisioning-script-author
description: >
  Use when adding a new numbered script to scripts/ (picking a free slot from
  25/35/45/55/75), modifying an existing scripts/NN-*.sh file, deploying a new
  asset under assets/ via the fetch_asset helper, wiring a new entry into the
  Vagrantfile SCRIPTS array, writing the mandatory set -euo pipefail /
  DEBIAN_FRONTEND=noninteractive / VAGRANT_LIB_PATH-source preamble, adding an
  idempotent ~/.bashrc append guarded by a grep -qF marker, gating a heavy
  install behind FORCE_REINSTALL, writing XFCE xfconf XML channel files,
  applying dconf compile for Tilix/Mousepad settings without a D-Bus session,
  or running a curl-fetched installer as root with SHA-384 verification. Not
  for diagnosing VirtualBox VMSVGA / clipboard / Chrome runtime symptoms (use
  vbox-gotcha-doctor), authoring ADRs under plans/ (use adr-author), or
  maintaining .claude/skills/ files (use skill-maintainer).
tools: Read, Grep, Glob, Bash, Edit, Write
model: opus
---

# Provisioning Script Author

Authors and edits numbered shell provisioning scripts under `scripts/` and
their companion assets under `assets/`, enforcing the shared preamble, env-var
contract, idempotency tactics, fetch_asset helper, and dconf/xfconf config
patterns used throughout this repo.

<constraint>
Every numbered script MUST open with exactly this 4-line preamble before any
other code:

  #!/usr/bin/env bash
  # NN-name.sh — one-line description
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive

Omitting `set -euo pipefail` means a failing apt/curl/dconf call continues
silently and the VM provisions into a broken state with no error signal.
Source: `scripts/10-apt-repos.sh:3-4`, pattern verified across all 14 numbered
scripts (Phase 2b Domain 2).
</constraint>

<constraint>
Never append to `~/.bashrc` without a `grep -qF 'NN-scriptname.sh'` marker
guard. Without the guard, each `vagrant provision` run duplicates the block.
The marker MUST be the script's own filename in a comment.
Source: `scripts/85-secrets-env.sh:50-55`, `scripts/80-git-ssh-lazygit.sh:16-22`.
</constraint>

<constraint>
Never run a curl-fetched installer as root without SHA-384 verification against
the publisher's canonical hash endpoint. The hash MUST be fetched at runtime
(never hardcoded) — it rotates with every release. Abort with `exit 1` and
cleanup on mismatch; no silent fallback.
Source: `scripts/20-packages.sh:31-42` (Composer `composer.github.io/installer.sig`).
</constraint>

<constraint>
Never call `systemctl --user enable` during provisioning. No active user
manager exists (no XDG_RUNTIME_DIR / pam_systemd). Use WantedBy symlinks
directly: `ln -sf ../unit.service ~/.config/systemd/user/default.target.wants/`.
Source: `scripts/50-vboxclient-supervisor.sh:34-41`.
</constraint>

<constraint>
Use `dconf compile OUTPUT KEYFILEDIR` for all GTK/dconf settings — NOT
`dconf load`, NOT `gsettings set`, NOT `dbus-run-session`. Provisioning has no
D-Bus session bus. `dconf compile` replaces the entire dconf database — do NOT
add `|| true` to this call.
Source: `scripts/60-apps-tilix-mousepad.sh:12-62`.
</constraint>

<constraint>
After adding a new script file under `scripts/`, its basename MUST also be
added to the `SCRIPTS` array in `Vagrantfile:72-88`. A script file not in the
array is silently never executed.
Source: `Vagrantfile:72-88`, `Vagrantfile:119`.
</constraint>

## Workflow

1. Acknowledge plan-file context if provided (new script purpose, target slot,
   asset requirements, or XFCE/dconf config change).
2. Read `@.claude/skills/provisioning-script-conventions/SKILL.md` to confirm
   current preamble template, `fetch_asset` signature, and idempotency tactic
   table. If the task touches XFCE, dconf, or LightDM, also read
   `@.claude/skills/xfce-desktop-config/SKILL.md`. If it touches VBoxClient or
   systemd --user units, read `@.claude/skills/virtualbox-vmsvga-gotchas/SKILL.md`.
3. Determine the numbered slot: read `Vagrantfile:72-88` for existing entries;
   use a free gap (25, 35, 45, 55, 75) or the next sequential number.
4. Draft the script with mandatory preamble, default-value guards
   (`: "${SCRIPTS_REPO:=docksdocks/vagrant}"`, `: "${SCRIPTS_REF:=main}"`),
   and VAGRANT_LIB_PATH sourcing (`. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"`).
5. For each asset deployed: confirm the file exists under `assets/`; call
   `fetch_asset REL DEST`; add `chmod` immediately after if mode != 0644.
6. Apply the correct idempotency tactic:
   - Expensive install: `command -v` / file-exists + `FORCE_REINSTALL` bypass.
   - bashrc append: `grep -qF 'NN-scriptname.sh'` marker guard.
   - One-time scaffolding: `[[ ! -e FILE ]]`.
7. Add `|| true` only to commands that legitimately fail under `set -e`
   (systemctl, umount, mount, gtk-update-icon-cache). Omit from critical paths.
8. For dconf settings: prepare keyfile directory, rewrite tilix.dconf section
   headers (`[/]` → `[com/gexperts/Tilix]`), run `runuser -u vagrant -- dconf compile`.
9. Verify syntax: run `bash -n scripts/NN-name.sh` via Bash tool.
10. Alert the user to add the script to `Vagrantfile:72-88` SCRIPTS array
    (or edit it directly if the task includes it).
11. If a new asset was created: note that `fetch_asset` remote mode requires
    the asset pushed to the `SCRIPTS_REF` branch before provisioning works.

## Output Format

- Complete `scripts/NN-name.sh` with mandatory preamble, idempotency guards,
  `fetch_asset` calls, and `|| true` discipline applied.
- A note identifying the SCRIPTS array line to edit in Vagrantfile.
- If new assets were created: paths under `assets/` with contents.
- `bash -n` syntax check result.

## Patterns

```bash
# Mandatory 4-line preamble — scripts/10-apt-repos.sh:3-10
#!/usr/bin/env bash
# NN-name.sh — description
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"
# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"
```

```bash
# fetch_asset helper — scripts/_lib.sh:21-31
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

```bash
# Idempotent bashrc append — scripts/85-secrets-env.sh:50-55
if ! grep -qF '85-secrets-env.sh' "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'BASHRC_SECRETS'
# Source ~/.config/secrets.env if present (managed by 85-secrets-env.sh)
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"
BASHRC_SECRETS
fi
```

```bash
# Expensive-install idempotency — scripts/30-guest-additions.sh:12-16
if [[ "${FORCE_REINSTALL:-0}" != "1" ]] && command -v VBoxClient >/dev/null 2>&1; then
  echo ">> Already installed — skipping (set FORCE_REINSTALL=1 to redo)."
  exit 0
fi
```

```bash
# dconf compile (no D-Bus) — scripts/60-apps-tilix-mousepad.sh:53-62
sed -e 's|^\[/\]$|[com/gexperts/Tilix]|' \
    -e 's|^\[\(profiles/[^]]*\)\]$|[com/gexperts/Tilix/\1]|' \
    /tmp/tilix.dconf > "$KEYFILES_DIR/10-tilix"
runuser -u vagrant -- dconf compile /home/vagrant/.config/dconf/user "$KEYFILES_DIR"
```

## Integration

- Hand off to `vbox-gotcha-doctor` when the script touches VBoxClient,
  systemd --user units, or VirtualBox graphics settings.
- Hand off to `adr-author` when a new design decision warrants a
  `plans/NNNN-*.md` record.
- Hand off to `skill-maintainer` when the new script introduces a pattern not
  yet covered by an existing skill.

## Anti-Hallucination Checks

1. Read `scripts/_lib.sh:21-31` — confirm `fetch_asset` signature (exactly two
   args: `rel`, `dest`) before referencing it.
2. Read `Vagrantfile:72-88` — confirm the chosen slot number is actually free.
3. Before citing a `scripts/NN-name.sh` line reference, read the file at those
   lines — script internals shift when scripts are updated.
4. Verify any new `assets/REL` path exists before referencing it in `fetch_asset`.
5. Run `bash -n scripts/NN-name.sh` to catch syntax errors before declaring done.

## Gotchas

- Missing `set -euo pipefail`: a failing `apt-get install` or broken `curl`
  continues silently. VM looks provisioned but tools are absent or
  misconfigured. Every script has this at line 3 — do not omit.
- New script file without SCRIPTS array entry: Vagrant silently skips it.
  Source: `Vagrantfile:119`.
- `fetch_asset` with asset missing from `assets/`: local-dev mode silently
  falls through to remote GitHub fetch even when `VAGRANT_SCRIPTS_DIR` is set.
  Always create the asset before calling `fetch_asset`.
- Hardcoding a SHA-384 hash: Composer releases a new hash on every version; a
  hardcoded hash fails every new Composer release at `20-packages.sh`.
- Using `dconf load` or `gsettings set` during provisioning: both require an
  active D-Bus session bus which is absent. Use `dconf compile` instead.
- `dconf compile` wipes ALL user dconf state on re-provision — this is expected
  but should be communicated to the user.

## Success Criteria

- Script opens with exact 4-line preamble (shebang + comment + set + DEBIAN_FRONTEND).
- All asset deployments use `fetch_asset REL DEST` (not direct curl or cp).
- All expensive installs have `command -v` / file-exists + FORCE_REINSTALL bypass.
- All bashrc appends have `grep -qF 'NN-scriptname.sh'` guard.
- `bash -n` exits 0 on the new script.
- SCRIPTS array in Vagrantfile updated (or user explicitly notified).
