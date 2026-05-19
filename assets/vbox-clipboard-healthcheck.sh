#!/usr/bin/env bash
# vbox-clipboard-healthcheck.sh — detect Oracle VirtualBox bug #5266 / #19234
# (VBoxClient --clipboard stays alive but its HGCM<->X11 bridge silently dies,
# logging "Converting VBox formats 'NONE' to ..." VERR_NOT_SUPPORTED) and
# restart the supervised helpers to re-establish the bridge.
#
# Triggered every 2 minutes by vbox-clipboard-healthcheck.timer. Required
# because the existing vbox-clipboard-unlock-watchdog.service only kicks on
# screen unlock, and on this box light-locker is intentionally disabled —
# so no D-Bus ScreenSaver signal ever fires.
set -eu

# Only consider journal lines since the unit's last (re)start. After a fix,
# the next tick sees only the new boot's log (no errors) and exits cleanly.
since=$(systemctl --user show -p ActiveEnterTimestamp --value \
          vbox-clipboard.service 2>/dev/null || true)
[ -n "$since" ] || exit 0

if journalctl --user -u vbox-clipboard.service \
     --since "$since" --no-pager 2>/dev/null \
   | grep -q "VBox formats 'NONE'"; then
  systemctl --user restart \
    vbox-clipboard.service vbox-draganddrop.service
fi
