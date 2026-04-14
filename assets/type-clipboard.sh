#!/usr/bin/env bash
# type-clipboard — types the X clipboard contents as synthetic keystrokes.
#
# Workaround for apps that mishandle bracketed paste (notably the Claude Code
# OAuth login prompt — upstream bug anthropics/claude-code#47670).
# Bound to Ctrl+Alt+V via XFCE keyboard shortcuts. Normal paste (Ctrl+Shift+V,
# Ctrl+V) is unaffected and remains the preferred option everywhere it works.
set -euo pipefail

content="$(xclip -o -selection clipboard 2>/dev/null || true)"
[ -z "$content" ] && exit 0

# --delay 12ms keeps Ink's input loop from dropping chars on fast typing.
exec xdotool type --clearmodifiers --delay 12 -- "$content"
