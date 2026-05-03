#!/usr/bin/env bash
# 51-vbox-autoresize.sh — xev-based auto-resize workaround while VBox GA 7.2.6
# fails to register VMSVGA auto-resize on Debian 13 Trixie
# (VirtualBox/virtualbox#568). See CLAUDE.md "Auto-resize not working".
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

mkdir -p /home/vagrant/.config/autostart
fetch_asset vbox-autoresize.desktop /home/vagrant/.config/autostart/vbox-autoresize.desktop
chown -R vagrant:vagrant /home/vagrant/.config/autostart
