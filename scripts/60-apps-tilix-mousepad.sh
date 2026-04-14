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

# ── Paste fallback: Ctrl+Alt+V types clipboard as keystrokes ──────
# Workaround for apps that mishandle bracketed paste (notably the Claude Code
# OAuth login prompt, upstream bug anthropics/claude-code#47670). Normal paste
# (Ctrl+Shift+V / Ctrl+V) is unaffected and remains preferred everywhere it
# works; this is an additive fallback, not a replacement.
fetch_asset type-clipboard.sh /usr/local/bin/type-clipboard
chmod 0755 /usr/local/bin/type-clipboard

# Register the binding via xfconf-query (idempotent; merges with system
# defaults instead of clobbering them as a full XML override would).
su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/<Primary><Alt>v" -n -t string \
  -s /usr/local/bin/type-clipboard' || \
  su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/<Primary><Alt>v" -t string \
  -s /usr/local/bin/type-clipboard' || true
su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/<Primary><Alt>v/override" -n -t bool -s true' || true
