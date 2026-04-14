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
         /home/vagrant/.config/systemd/user/default.target.wants

# Remove the pre-fix VBoxClient-all autostart (superseded by supervised units)
rm -f /home/vagrant/.config/autostart/vboxclient-all.desktop

fetch_asset systemd/vbox-clipboard.service   /home/vagrant/.config/systemd/user/vbox-clipboard.service
fetch_asset systemd/vbox-draganddrop.service /home/vagrant/.config/systemd/user/vbox-draganddrop.service

# Enable the user units by creating the WantedBy symlinks directly
# (avoids needing XDG_RUNTIME_DIR / an active user manager during provision)
ln -sf ../vbox-clipboard.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard.service
ln -sf ../vbox-draganddrop.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-draganddrop.service

# XDG autostart: import DISPLAY/XAUTHORITY into the user manager, ensure
# the supervised services are running for this session, and launch the
# one-shot helpers that don't need supervision.
fetch_asset vboxclient-session.desktop /home/vagrant/.config/autostart/vboxclient-session.desktop

chown -R vagrant:vagrant /home/vagrant/.config/autostart /home/vagrant/.config/systemd
