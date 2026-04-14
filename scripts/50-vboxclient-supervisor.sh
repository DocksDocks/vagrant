#!/usr/bin/env bash
# 50-vboxclient-supervisor.sh — supervise VBoxClient --clipboard / --draganddrop
# via systemd --user (upstream helpers terminate silently on X events; see
# VirtualBox #5266/#6150, NixOS/nixpkgs#65542). See plans/0001-clipboard-supervisor.md.
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

mkdir -p /home/vagrant/.config/autostart \
         /home/vagrant/.config/systemd/user \
         /home/vagrant/.config/systemd/user/default.target.wants \
         /home/vagrant/.local/bin

# Remove the pre-fix VBoxClient-all autostart (superseded by supervised units)
rm -f /home/vagrant/.config/autostart/vboxclient-all.desktop

fetch_asset systemd/vbox-clipboard.service   /home/vagrant/.config/systemd/user/vbox-clipboard.service
fetch_asset systemd/vbox-draganddrop.service /home/vagrant/.config/systemd/user/vbox-draganddrop.service

# Optional post-unlock watchdog: kicks the supervised clipboard helper on
# screen-unlock (XFCE/freedesktop ScreenSaver ActiveChanged=false). Belt-and-
# braces on top of Restart=always — only matters if the user re-enables screen
# locking. See Oracle VBox #5266 / #19234.
fetch_asset vbox-clipboard-unlock-watchdog.sh /home/vagrant/.local/bin/vbox-clipboard-unlock-watchdog
chmod 0755 /home/vagrant/.local/bin/vbox-clipboard-unlock-watchdog
fetch_asset systemd/vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/vbox-clipboard-unlock-watchdog.service

# Enable the user units by creating the WantedBy symlinks directly
# (avoids needing XDG_RUNTIME_DIR / an active user manager during provision)
ln -sf ../vbox-clipboard.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard.service
ln -sf ../vbox-draganddrop.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-draganddrop.service
ln -sf ../vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard-unlock-watchdog.service

# XDG autostart: import DISPLAY/XAUTHORITY into the user manager, ensure
# the supervised services are running for this session, and launch the
# one-shot helpers that don't need supervision.
fetch_asset vboxclient-session.desktop /home/vagrant/.config/autostart/vboxclient-session.desktop

chown -R vagrant:vagrant \
  /home/vagrant/.config/autostart /home/vagrant/.config/systemd /home/vagrant/.local
