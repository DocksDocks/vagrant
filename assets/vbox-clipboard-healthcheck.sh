#!/usr/bin/env bash
# vbox-clipboard-healthcheck.sh — detect Oracle VirtualBox bug #5266 / #19234
# (VBoxClient --clipboard stays alive but its HGCM<->X11 bridge silently dies)
# and restart the supervised helpers to re-establish the bridge.
#
# Two detectors, cheapest first:
#   1. Active read-probe (non-destructive): if the CLIPBOARD selection
#      advertises a text target but the content can't be read, the bridge has
#      degraded even though no app has tried to paste yet. Catches the failure
#      PROACTIVELY — the journal-scan below only sees it after a real paste
#      fails and logs the conversion error.
#   2. Journal-scan: two sister signatures, both VERR_NOT_SUPPORTED:
#        - "Converting VBox formats 'NONE' to ..."           (source-side dead)
#        - "Converting VBox formats '<X>' to 'INVALID' ..."  (X11-side dead)
#
# Triggered every 2 minutes by vbox-clipboard-healthcheck.timer. The real-time
# vbox-clipboard-bridge-watcher.service handles the same journal signature with
# ~1s latency, so this timer is the stateless backstop + the proactive probe.
set -eu

restart_bridge() {
  systemctl --user restart vbox-clipboard.service vbox-draganddrop.service
  exit 0
}

# --- Detector 1: active, non-destructive read-probe --------------------------
# Read-only (xclip -o): never writes to the clipboard, so it cannot clobber the
# user's content — unlike a write+read probe, which plans/0004 rejected for that
# reason. Needs DISPLAY/XAUTHORITY, imported into the user manager at login by
# vboxclient-session.desktop; if absent (e.g. pre-login), skip to the log-scan.
if command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  targets=$(timeout 5 xclip -selection clipboard -o -t TARGETS 2>/dev/null || true)
  case "$targets" in
    *UTF8_STRING*|*STRING*)
      # Text IS advertised. If neither text target can actually be pulled, the
      # owner is present but delivery is broken -> degraded bridge, restart.
      if ! timeout 5 xclip -selection clipboard -o -t UTF8_STRING >/dev/null 2>&1 \
         && ! timeout 5 xclip -selection clipboard -o -t STRING  >/dev/null 2>&1; then
        restart_bridge
      fi
      ;;
    # Empty / no text owner: ambiguous (genuinely empty vs fully detached).
    # Don't restart — a false positive would clobber selection ownership every
    # 2 min on an idle clipboard. Fall through to the journal-scan.
  esac
fi

# --- Detector 2: journal-scan since the unit's last (re)start ----------------
# After a restart the journal-since-ActiveEnter window is empty, so the next
# tick early-exits with no restart — idempotent, no state file needed.
since=$(systemctl --user show -p ActiveEnterTimestamp --value \
          vbox-clipboard.service 2>/dev/null || true)
[ -n "$since" ] || exit 0

if journalctl --user -u vbox-clipboard.service \
     --since "$since" --no-pager 2>/dev/null \
   | grep -qE "VBox formats 'NONE'|to 'INVALID' for X11"; then
  restart_bridge
fi
