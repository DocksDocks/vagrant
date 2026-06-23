#!/usr/bin/env bash
# vbox-clipboard-bridge-watcher.sh — react in real time to the degraded
# HGCM<->X11 bridge signature in VBoxClient --clipboard's journal and restart
# the supervised helpers immediately, instead of waiting up to 2 min for the
# periodic healthcheck timer (Oracle VirtualBox #5266 / #19234).
#
# Complements vbox-clipboard-healthcheck.{timer,service} (Layer 5): the timer
# is the stateless backstop + active read-probe; this watcher cuts recovery
# latency on a *logged* failure from <=2 min down to ~1s.
#
# Why tailing the journal is safe here (plans/0004 rejected `journalctl -f`):
#   - `-n0` starts at the journal tail, so stale lines from a previous unit
#     lifetime are never replayed — the cursor-file concern 0004 raised is moot.
#   - Restart=always on the unit re-establishes the follow cleanly if it dies.
#   - A 10s debounce stops a burst of error lines from triggering a restart
#     storm; any lines emitted just before the restart land inside the cooldown.
set -eu

# Follow only NEW lines of the clipboard unit's journal (-n0 = no history).
# The follow tracks the unit by name, so it survives the restarts it triggers.
exec journalctl --user -u vbox-clipboard.service -f -n0 -o cat 2>/dev/null |
while read -r line; do
  case "$line" in
    *"VBox formats 'NONE'"*|*"to 'INVALID' for X11"*)
      now=$(date +%s)
      if [ $(( now - ${last:-0} )) -ge 10 ]; then
        last=$now
        systemctl --user restart \
          vbox-clipboard.service vbox-draganddrop.service 2>/dev/null || true
      fi
      ;;
  esac
done
