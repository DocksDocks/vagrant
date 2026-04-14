#!/usr/bin/env bash
# 30-guest-additions.sh — install VirtualBox Guest Additions from ISO.
#
# Idempotency: on re-provision, skip the ISO download + module rebuild if GA
# userland (VBoxClient) is already installed, unless FORCE_REINSTALL=1 is set.
# The kernel module build on 6.19+ fails anyway (__flush_tlb_all namespace
# change) and the in-kernel vboxguest covers basic functionality, so the
# expensive part here is the ISO download (~80 MB) and the always-failing
# module compile — both pure waste on re-provision.
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
VBOX_VERSION=$(cat /home/vagrant/.vbox_version 2>/dev/null || VBoxControl --version 2>/dev/null | head -1 | sed 's/r.*//' || echo "7.2.6")
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
