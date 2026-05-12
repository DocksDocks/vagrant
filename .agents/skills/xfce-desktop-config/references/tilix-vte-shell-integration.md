# Tilix VTE Shell Integration

<constraint>
The symlink `ln -s vte-2.91.sh /etc/profile.d/vte.sh` AND the `~/.bashrc` append are BOTH required. The symlink alone doesn't help because `/etc/profile.d/` is login-shell only; Tilix spawns interactive non-login shells. Source: `scripts/60-apps-tilix-mousepad.sh:64-83`.
</constraint>

## The Problem

Tilix shows "Configuration Issue Detected" when VTE shell integration hooks are not sourced in the shell it spawns.

VTE provides `/etc/profile.d/vte-2.91.sh` which exports shell integration functions (OSC 7 cwd tracking, prompt markers). But `/etc/profile.d/` is sourced only by login shells (`bash -l`). Tilix spawns interactive non-login shells by default (`bash -i`). The hooks never load.

Source: `scripts/60-apps-tilix-mousepad.sh:64-70` (comment block), [Tilix VTE config docs](https://gnunn1.github.io/tilix-web/manual/vteconfig/)

## The Fix

**Step 1: Create the canonical `vte.sh` symlink**

```bash
if [[ -f /etc/profile.d/vte-2.91.sh && ! -e /etc/profile.d/vte.sh ]]; then
  ln -s vte-2.91.sh /etc/profile.d/vte.sh
fi
```

Source: `scripts/60-apps-tilix-mousepad.sh:71-73`. Debian ships `vte-2.91.sh`; the canonical name Tilix looks for is `vte.sh`. The symlink bridges the naming gap.

**Step 2: Source from `~/.bashrc` with a guard**

```bash
if ! grep -q 'TILIX_ID' /home/vagrant/.bashrc 2>/dev/null; then
  cat >> /home/vagrant/.bashrc <<'BASHRC_VTE'

# VTE shell integration for Tilix (OSC 7 cwd + prompt markers)
if [ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]; then
  . /etc/profile.d/vte.sh
fi
BASHRC_VTE
fi
```

Source: `scripts/60-apps-tilix-mousepad.sh:74-83`. The guard `[ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]` ensures the hooks only load when running under VTE (Tilix) — they are harmless in other contexts but the guard is best practice.

## What VTE Shell Integration Provides

- **OSC 7**: terminal notifies Tilix of cwd changes; Tilix can open new splits in the current directory.
- **Prompt markers**: Tilix can navigate between prompts (Ctrl+Up/Down).

Without these, Tilix still works but shows the dialog and cannot use cwd-aware split pane open.

## Idempotency

The `grep -q 'TILIX_ID'` guard prevents duplicate appends to `~/.bashrc` on re-provision. The symlink creation uses `! -e /etc/profile.d/vte.sh` to skip if already present.

## Gotchas

**Tilix still shows dialog after provisioning**: check both the symlink and the bashrc append. The dialog appears when either is missing. Run `ls -la /etc/profile.d/vte*.sh` and `grep -n TILIX_ID /home/vagrant/.bashrc`.

**`vte-2.91.sh` filename varies by Debian release**: future Debian releases may ship `vte-0.76.sh` or similar. The provisioning code checks for `vte-2.91.sh` by name. If it doesn't exist, the symlink is skipped silently (the `if [[ -f ...` guard). The `~/.bashrc` append still runs, but `. /etc/profile.d/vte.sh` fails silently (file doesn't exist) — Tilix will show the dialog again. Update the filename in `scripts/60-apps-tilix-mousepad.sh:71` after a Debian upgrade.

**`TILIX_ID` vs `VTE_VERSION`**: `TILIX_ID` is set by Tilix specifically; `VTE_VERSION` is set by any VTE-based terminal. The OR condition means the hooks load in other VTE terminals too (e.g. GNOME Terminal). This is intentional — VTE integration is beneficial in all VTE terminals.
