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
# `grep -oE` exits 1 on no match, falling through to the literal default.
VBOX_VERSION=$( \
  cat /home/vagrant/.vbox_version 2>/dev/null \
  || VBoxControl --version 2>/dev/null | head -1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' \
  || echo "7.2.6" \
)
# `cat` succeeds with status 0 even when the file is empty, so the fallback
# chain above doesn't catch an empty .vbox_version. Belt-and-braces default.
VBOX_VERSION="${VBOX_VERSION:-7.2.6}"
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
