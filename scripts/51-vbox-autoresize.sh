#!/usr/bin/env bash
# 51-vbox-autoresize.sh — xev-based auto-resize workaround while VBox GA 7.2.6
# kernel modules fail to build on kernel 6.19+. See CLAUDE.md "Auto-resize not working".
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

mkdir -p /home/vagrant/.config/autostart
fetch_asset vbox-autoresize.desktop /home/vagrant/.config/autostart/vbox-autoresize.desktop
chown -R vagrant:vagrant /home/vagrant/.config/autostart
