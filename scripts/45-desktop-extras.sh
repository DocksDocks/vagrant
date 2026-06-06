#!/usr/bin/env bash
# 45-desktop-extras.sh — Ubuntu-style screenshots + Thunar Places bookmarks.
#
# Two small desktop-UX touches that XFCE doesn't ship by default:
#   1. Print key → drag-select a region, auto-save to ~/Pictures/Screenshots,
#      auto-copy to the clipboard (the screenshot-region wrapper). No chooser
#      dialog, no save-as dialog — matches GNOME/Ubuntu's PrtSc behaviour.
#   2. Downloads + Pictures pinned in the Thunar sidebar (GTK bookmarks).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# Extras de desktop XFCE (PrtSc estilo Ubuntu, bookmarks do Thunar, notifyd) são
# parte da personalização específica do Debian. Em Ubuntu pulamos (ver 41 e a
# nota de multi-plataforma no Vagrantfile) — fica o desktop padrão.
if [ "$(. /etc/os-release && echo "$ID")" != "debian" ]; then
  echo ">> $(. /etc/os-release && echo "$ID") detectado — pulando extras de desktop XFCE (apenas Debian)."
  exit 0
fi

# ── Screenshot wrapper (region → save + clipboard) ──────
# fetch_asset installs 0644; the wrapper must be executable.
fetch_asset bin/screenshot-region /usr/local/bin/screenshot-region
chmod 0755 /usr/local/bin/screenshot-region

# Keyboard-shortcuts channel, seeded in /etc/xdg so xfconfd picks it up on a
# fresh user's first login (same mechanism as the panel seed in 40-xfce-base).
# It is the stock XFCE shortcut set with one change: Print runs the wrapper
# above instead of opening xfce4-screenshooter's chooser. Seed-only — it does
# NOT overwrite an existing user's ~/.config copy, so re-provisioning never
# clobbers shortcuts you've customised. (On this box the binding was already
# applied live via xfconf-query.)
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
fetch_asset xfce4-keyboard-shortcuts.xml \
  /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml

# Notification toasts disappear after 2s instead of lingering ~15s — the
# screenshot confirmation in particular should be brief. Same /etc/xdg seed
# mechanism; on this box it was applied live via xfconf-query.
fetch_asset xfce4-notifyd.xml \
  /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml

# ── XDG dirs the wrapper + bookmarks point at ──────────
# xdg-user-dirs creates these on first login, but the screenshot target and
# the bookmarks below reference them, so make sure they exist now.
mkdir -p /home/vagrant/Downloads \
         /home/vagrant/Pictures/Screenshots

# ── Thunar Places: pin Downloads + Pictures ────────────
# GTK bookmarks are user-only (no /etc/xdg seed), so write the file directly.
# Idempotent: only append a folder that isn't already bookmarked (matching the
# URI at line start so an entry with a custom label isn't duplicated).
BOOKMARKS=/home/vagrant/.config/gtk-3.0/bookmarks
mkdir -p "$(dirname "$BOOKMARKS")"
touch "$BOOKMARKS"
for dir in Downloads Pictures; do
  uri="file:///home/vagrant/${dir}"
  grep -qE "^${uri}([[:space:]]|\$)" "$BOOKMARKS" || echo "$uri" >> "$BOOKMARKS"
done

# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.
