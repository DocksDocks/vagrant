#!/usr/bin/env bash
# 15-grub-quickboot.sh — boot straight into Debian, skipping the 1-second GRUB
# menu the bento/debian-13 base box draws on every cold boot.
#
# The base box ships /etc/default/grub with a short, *visible* timeout
# (GRUB_TIMEOUT=1 and a non-hidden GRUB_TIMEOUT_STYLE), so GRUB renders its menu
# for one second on each `vagrant up`/`reload` before auto-booting the default
# entry. Setting the timeout to 0 and the style to `hidden` makes GRUB boot the
# default entry immediately without drawing the menu. The menu stays reachable
# for recovery: hold Shift (BIOS) or tap Esc during boot to bring it back, so the
# "Advanced options"/recovery entries are never lost.
#
# Unrelated to the grub-pc/install_devices debconf seed in 10-apt-repos.sh —
# that only stops `apt upgrade` from prompting; this only changes menu display.
#
# Idempotent: rewrites the two keys in place and runs update-grub only when a
# value actually changed.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

GRUB_DEFAULT_FILE=/etc/default/grub

# Defensive: don't abort provisioning over a cosmetic boot tweak if the base box
# ever ships without grub-pc (e.g. a non-GRUB or grub-efi-only image).
if [[ ! -f "$GRUB_DEFAULT_FILE" ]]; then
  echo ">> $GRUB_DEFAULT_FILE ausente; pulando ajuste de boot do GRUB." >&2
  exit 0
fi

changed=0

# ensure_grub_key KEY VALUE — make KEY=VALUE the active assignment in
# /etc/default/grub: replace an existing uncommented `KEY=...` line, or append
# one if none exists. A pre-existing commented `#KEY=...` line is left as-is
# (the active line wins). Re-runs are no-ops once the value already matches.
ensure_grub_key() {
  local key="$1" desired="$1=$2"
  if grep -qxF "$desired" "$GRUB_DEFAULT_FILE"; then
    return 0
  fi
  if grep -qE "^${key}=" "$GRUB_DEFAULT_FILE"; then
    sed -i "s|^${key}=.*|${desired}|" "$GRUB_DEFAULT_FILE"
  else
    printf '%s\n' "$desired" >> "$GRUB_DEFAULT_FILE"
  fi
  changed=1
}

ensure_grub_key GRUB_TIMEOUT 0
ensure_grub_key GRUB_TIMEOUT_STYLE hidden

if [[ "$changed" -eq 1 ]]; then
  echo ">> Boot direto habilitado (GRUB_TIMEOUT=0, GRUB_TIMEOUT_STYLE=hidden); regenerando grub.cfg..."
  update-grub
else
  echo ">> GRUB já configurado para boot direto; nada a fazer."
fi
