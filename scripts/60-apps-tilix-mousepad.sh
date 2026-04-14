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

# ── Paste workarounds for Claude Code OAuth (anthropics/claude-code#47670) ──
#
# Two complementary paths so the OAuth `Paste code here` prompt can receive
# the code reliably:
#
#   1) `claude-login` — opens xfce4-terminal with MiscDisableBracketedPaste=TRUE
#      (terminalrc below). In that terminal the VTE ignores DECSET 2004, so
#      normal Ctrl+Shift+V works for the OAuth code. Preferred path.
#
#   2) Ctrl+Alt+V — xdotool types the clipboard as synthetic keystrokes,
#      bypassing bracketed paste. Secondary fallback; requires logout/login
#      after provisioning so xfsettingsd picks up the shortcut.
#
# Normal Ctrl+Shift+V / Ctrl+V in Tilix remain unchanged and are still the
# preferred paste everywhere they work, including the main Claude Code chat.

# --- (1) claude-login + xfce4-terminal config --------------------------------
fetch_asset claude-login.sh /usr/local/bin/claude-login
chmod 0755 /usr/local/bin/claude-login

# xfce4-terminal profile: disable bracketed paste at the VTE level so the
# `claude-login` session can paste the OAuth code with regular Ctrl+Shift+V.
fetch_asset xfce4-terminalrc /home/vagrant/.config/xfce4/terminal/terminalrc
chown -R vagrant:vagrant /home/vagrant/.config/xfce4/terminal

# --- (2) type-clipboard keybinding (secondary fallback) ----------------------
fetch_asset type-clipboard.sh /usr/local/bin/type-clipboard
chmod 0755 /usr/local/bin/type-clipboard

# Register <Primary><Alt>v via xfconf-query. Wrap both the initial create
# and subsequent updates so re-provisioning is a no-op.
su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/<Primary><Alt>v" -n -t string \
  -s /usr/local/bin/type-clipboard' || \
  su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/<Primary><Alt>v" -t string \
  -s /usr/local/bin/type-clipboard' || true
# `override` is a SIBLING of the bindings under /commands/custom, not a child
# of any single binding. It tells xfsettingsd to override any default binding
# on the same key combo.
su - vagrant -c 'dbus-launch xfconf-query -c xfce4-keyboard-shortcuts \
  -p "/commands/custom/override" -n -t bool -s true' || true
