#!/usr/bin/env bash
# 30-guest-additions.sh — install VirtualBox Guest Additions from ISO.
#
# Idempotency: on re-provision, skip the ISO download + module rebuild if GA
# userland (VBoxClient) is already installed, unless FORCE_REINSTALL=1 is set.
# Modules build fine on Trixie's 6.12 kernel; the broken piece is the GA
# auto-resize service registration (VirtualBox/virtualbox#568), handled by the
# xev workaround in scripts/51-vbox-autoresize.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ "${FORCE_REINSTALL:-0}" != "1" ]] && command -v VBoxClient >/dev/null 2>&1; then
  echo ">> VirtualBox Guest Additions already installed — skipping (set FORCE_REINSTALL=1 to redo)."
  systemctl enable vboxadd-service 2>/dev/null || true
  exit 0
fi

# ── VirtualBox Guest Additions (clipboard + auto-resize) ──
echo ">> Instalando VirtualBox Guest Additions..."
apt-get install -y -qq linux-headers-amd64 dkms
# Extract just the leading semver-shaped portion from whatever VBoxControl
# reports — "7.2.6r170137", "7.2.6-rc1", "7.2.6_Beta1" all collapse to "7.2.6".
# bento boxes always write /home/vagrant/.vbox_version during box build, so
# the file path is the primary source of truth. VBoxControl is the fallback
# when GA was pre-installed by some other means. Abort if neither works:
# silently picking a hardcoded default (e.g. "7.2.6") would download a
# possibly-stale ISO that no longer matches the host's VBox version, and
# masks the real "the base box is broken" failure mode.
VBOX_VERSION=$( \
  cat /home/vagrant/.vbox_version 2>/dev/null \
  || VBoxControl --version 2>/dev/null | head -1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' \
  || true \
)
# `cat` succeeds with status 0 even when the file is empty, so check the
# resulting value, not the exit chain.
if [[ -z "$VBOX_VERSION" ]]; then
  echo "✗ Could not detect VirtualBox Guest Additions version." >&2
  echo "   /home/vagrant/.vbox_version is missing or empty, and VBoxControl is unavailable." >&2
  echo "   Set the version manually before re-provisioning, e.g.:" >&2
  echo "     echo 7.2.6 | sudo tee /home/vagrant/.vbox_version" >&2
  exit 1
fi
VBOX_ISO="/home/vagrant/VBoxGuestAdditions_${VBOX_VERSION}.iso"
if [ ! -f "$VBOX_ISO" ]; then
  curl -fsSL -o "$VBOX_ISO" "https://download.virtualbox.org/virtualbox/${VBOX_VERSION}/VBoxGuestAdditions_${VBOX_VERSION}.iso" || true
fi
if [ -f "$VBOX_ISO" ]; then
  mount -o loop "$VBOX_ISO" /mnt 2>/dev/null || true
  /mnt/VBoxLinuxAdditions.run --nox11 || true
  umount /mnt 2>/dev/null || true
  rm -f "$VBOX_ISO"
fi
# Ensure GA services (including VBoxDRMClient for VMSVGA resize) are enabled
systemctl enable vboxadd-service 2>/dev/null || true
