#!/usr/bin/env bash
# claude-login — opens xfce4-terminal with bracketed paste disabled at the VTE
# level and runs `claude /login`. Works around anthropics/claude-code#47670:
# in Tilix (and any terminal with bracketed paste enabled), the OAuth
# `Paste code here if prompted >` input silently drops pasted content because
# Claude Code mishandles the \e[200~…\e[201~ markers on that screen.
#
# xfce4-terminal honors MiscDisableBracketedPaste=TRUE, which calls
# vte_terminal_set_enable_bracketed_paste(FALSE) on the widget and thereby
# ignores the app's DECSET 2004 request entirely. Inside that terminal,
# normal Ctrl+Shift+V pastes the OAuth code as plain bytes and login works.
#
# After a successful login the auth token is persisted to
# ~/.claude and you can go back to using `claude` in Tilix normally.
#
# Remove this wrapper (and the terminalrc tweak) once #47670 ships upstream.
set -euo pipefail

if ! command -v xfce4-terminal >/dev/null 2>&1; then
  echo "claude-login: xfce4-terminal is not installed." >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "claude-login: the 'claude' binary is not on PATH." >&2
  echo "  Ensure ~/.local/bin is in PATH (see scripts/70-nodejs-claude.sh)." >&2
  exit 1
fi

# --hold keeps the window open after claude exits so the user can read any
# final output (including the 'Logged in' confirmation).
exec xfce4-terminal --hold --title="claude /login (bracketed paste disabled)" \
  --command="$(command -v claude) /login"
