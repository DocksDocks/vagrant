#!/usr/bin/env bash
# 60-apps-tilix-mousepad.sh — Mousepad (gsettings) + Tilix (dconf load).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# Bypass dbus entirely by writing vagrant's dconf user database directly with
# `dconf compile`. Background:
#
# `dconf load` and `gsettings set` both go through dconf-service over the
# session bus. During provisioning vagrant has no real login session, so we
# spawn a one-shot bus with `dbus-run-session`. That worked for the first two
# calls (Mousepad gsettings) but the third (Tilix `dconf load`) consistently
# failed with `Failed to bind socket "/tmp/dbus-…": Permission denied` — the
# dbus-daemon under bento/debian-13's `tmp.mount` couldn't bind there, and
# despite multiple workarounds (loginctl enable-linger, env -u, runuser -l,
# pre-creating /run/user/$UID) the third call kept falling back to /tmp.
#
# `dconf compile OUTPUT KEYFILEDIR` writes a binary GVDB straight to disk with
# no bus involved — that's how system-wide /etc/dconf/db/* are built. The
# user db is the same format at ~/.config/dconf/user. We collect both Mousepad
# and Tilix settings as keyfiles in a temp dir and compile them in one shot.
#
# Caveat: dconf compile *replaces* the output db. That's fine here because
# both apps' settings live in this single payload, and any user-level dconf
# changes during provisioning would be wiped on re-provision anyway.
#
# Format conversion: tilix.dconf uses `dconf load` syntax (`[/]` for the
# subtree root, `[profiles/UUID]` for nested paths). Keyfile syntax for
# `dconf compile` uses absolute paths without leading slash, so we rewrite
# the section headers to live under com/gexperts/Tilix/.

KEYFILES_DIR=$(mktemp -d)
trap 'rm -rf "$KEYFILES_DIR" /tmp/tilix.dconf' EXIT

# ── Mousepad: Solarized Dark + Line Numbers ─────────────
cat >"$KEYFILES_DIR/00-mousepad" <<'EOF'
[org/xfce/mousepad/preferences/view]
show-line-numbers=true
color-scheme='solarized-dark'
EOF

# ── Tilix: configuração do terminal ──────────────────────
# Tilix identifies profiles by UUID — we set a fixed UUID as the default profile.
fetch_asset tilix.dconf /tmp/tilix.dconf
# Translate dconf-load → keyfile sections. `[/]` is the subtree root, so it
# becomes `[com/gexperts/Tilix]`; nested paths get the same prefix.
sed -e 's|^\[/\]$|[com/gexperts/Tilix]|' \
    -e 's|^\[\(profiles/[^]]*\)\]$|[com/gexperts/Tilix/\1]|' \
    /tmp/tilix.dconf > "$KEYFILES_DIR/10-tilix"

install -d -o vagrant -g vagrant /home/vagrant/.config/dconf
chown -R vagrant:vagrant "$KEYFILES_DIR"
# No `|| true`: this is the custom palette + font. Silent failure means the
# user opens Tilix, sees the default ugly theme, and assumes the box is
# broken. Fail loud so a regression is visible in the provision log.
runuser -u vagrant -- dconf compile /home/vagrant/.config/dconf/user "$KEYFILES_DIR"

# ── VTE shell integration (silences "Configuration Issue Detected" dialog) ──
# Tilix requires VTE's bash hooks (OSC 7 cwd tracking, prompt markers) sourced
# in interactive shells. Debian ships /etc/profile.d/vte-2.91.sh, but /etc/profile.d
# is only sourced by login shells — Tilix spawns interactive non-login shells, so
# the hooks never load and Tilix flags it. Symlink to the canonical vte.sh path
# and source it from ~/.bashrc when running under VTE.
# https://gnunn1.github.io/tilix-web/manual/vteconfig/
if [[ -f /etc/profile.d/vte-2.91.sh && ! -e /etc/profile.d/vte.sh ]]; then
  ln -s vte-2.91.sh /etc/profile.d/vte.sh
fi
if ! grep -q 'TILIX_ID' /home/vagrant/.bashrc 2>/dev/null; then
  cat >> /home/vagrant/.bashrc <<'BASHRC_VTE'

# VTE shell integration for Tilix (OSC 7 cwd + prompt markers)
if [ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]; then
  . /etc/profile.d/vte.sh
fi
BASHRC_VTE
  # Ownership of ~/.bashrc is corrected in scripts/55-permissions.sh.
fi
