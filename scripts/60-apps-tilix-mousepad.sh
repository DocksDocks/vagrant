#!/usr/bin/env bash
# 60-apps-tilix-mousepad.sh — Mousepad (gsettings) + Tilix (dconf load).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  # Local-dev mode: the repo is mounted at /vagrant on the guest (default shared folder).
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}

# ── Mousepad: Solarized Dark + Line Numbers ─────────────
su - vagrant -c 'dbus-launch gsettings set org.xfce.mousepad.preferences.view show-line-numbers true' || true
su - vagrant -c 'dbus-launch gsettings set org.xfce.mousepad.preferences.view color-scheme "solarized-dark"' || true

# ── Tilix: configuração do terminal ──────────────────────
# Uses dconf directly instead of gsettings to avoid schema compilation issues.
# Tilix identifies profiles by UUID — we set a fixed UUID as the default profile.
fetch_asset tilix.dconf /tmp/tilix.dconf
chown vagrant:vagrant /tmp/tilix.dconf
su - vagrant -c 'dbus-launch dconf load /com/gexperts/Tilix/ < /tmp/tilix.dconf' || true
rm -f /tmp/tilix.dconf

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
  chown vagrant:vagrant /home/vagrant/.bashrc
fi
