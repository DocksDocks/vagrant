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

# dbus-launch in `su - vagrant -c …` was racing PAM's session setup and dying
# with `Failed to bind socket "/tmp/dbus-…": Permission denied`, which silently
# dropped both the Mousepad gsettings calls and the Tilix dconf load (custom
# palette + JetBrainsMono font). Switch to dbus-run-session: it's the modern,
# scripted alternative — spawns a one-shot session bus, runs the command, tears
# the daemon down on exit, and doesn't try to integrate with an X session.
#
# vagrant has no live login session at provision time, so /run/user/$UID
# (where dbus-run-session prefers to drop its socket) doesn't exist. Create it
# ourselves; if systemd-logind later tmpfs-mounts on top, our directory just
# gets shadowed — harmless, since the dconf user db lives in $HOME.
VAGRANT_UID=$(id -u vagrant)
RUNTIME_DIR="/run/user/${VAGRANT_UID}"
install -d -m 0700 -o vagrant -g vagrant "$RUNTIME_DIR"
chmod 1777 /tmp  # defensive: dbus-daemon falls back to /tmp if RUNTIME_DIR fails

DBUS_RUN="XDG_RUNTIME_DIR='$RUNTIME_DIR' dbus-run-session --"

# ── Mousepad: Solarized Dark + Line Numbers ─────────────
su - vagrant -c "$DBUS_RUN gsettings set org.xfce.mousepad.preferences.view show-line-numbers true" || true
su - vagrant -c "$DBUS_RUN gsettings set org.xfce.mousepad.preferences.view color-scheme solarized-dark" || true

# ── Tilix: configuração do terminal ──────────────────────
# Uses dconf directly instead of gsettings to avoid schema compilation issues.
# Tilix identifies profiles by UUID — we set a fixed UUID as the default profile.
fetch_asset tilix.dconf /tmp/tilix.dconf
chown vagrant:vagrant /tmp/tilix.dconf
# No `|| true` here: this is the custom palette + font. Silent failure means
# the user opens Tilix, sees the default ugly theme, and assumes the box is
# broken. Fail loud so a regression is visible in the provision log.
su - vagrant -c "$DBUS_RUN dconf load /com/gexperts/Tilix/ < /tmp/tilix.dconf"
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
