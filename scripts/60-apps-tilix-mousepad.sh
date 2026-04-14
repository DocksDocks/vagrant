#!/usr/bin/env bash
# 60-apps-tilix-mousepad.sh — Mousepad (gsettings) + Tilix (dconf load).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" ]]; then
    install -D -m 0644 "${VAGRANT_SCRIPTS_DIR}/../assets/${rel}" "$dest"
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
