#!/usr/bin/env bash
# vbox-clipboard-unlock-watchdog.sh — kick the supervised VBoxClient --clipboard
# helper whenever the XFCE/freedesktop screensaver becomes inactive (unlocked).
#
# Works around Oracle VirtualBox bug #5266 / #19234, where VBoxClient --clipboard
# terminates silently on X-event storms during lock/unlock. The service-level
# Restart=always handles the silent death, but on unlock the restarted helper
# can race the X session re-grab and still end up broken — kicking it again
# right after the unlock signal clears that race.
set -eu

# dbus-monitor streams lines like:
#   signal ... interface=org.freedesktop.ScreenSaver; member=ActiveChanged
#      boolean false
# We want to fire on "ActiveChanged false" = screen unlocked.
exec dbus-monitor --session \
  "interface=org.freedesktop.ScreenSaver,member=ActiveChanged" 2>/dev/null |
while read -r line; do
  case "$line" in
    *"boolean false"*)
      # Small delay lets the X session finish re-grabbing before we reconnect.
      sleep 1
      systemctl --user try-restart \
        vbox-clipboard.service vbox-draganddrop.service 2>/dev/null || true
      ;;
  esac
done
