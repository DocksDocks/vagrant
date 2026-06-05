#!/usr/bin/env bash
# 66-vscode.sh — Visual Studio Code: user settings + extensions.
#
# The `code` package is installed from Microsoft's apt repo (added in
# 10-apt-repos.sh, installed in 20-packages.sh). This script deploys the user
# settings.json and installs the extension list (assets/vscode/*).
#
# Idempotency: `code --install-extension` skips already-installed extensions
# (FORCE_REINSTALL=1 adds --force to redo them); settings.json is seeded only on
# the FIRST provision (guarded by /var/lib/vagrant-provisioned, created by
# 99-finalize.sh) so re-provisioning never clobbers changes you made in the GUI
# — same contract as the other per-user config seeds.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

FORCE="${FORCE_REINSTALL:-0}"

# `code` may be absent if the Microsoft repo failed (e.g. transient network).
# Don't abort the whole provision — just skip VS Code config.
if ! command -v code >/dev/null 2>&1; then
  echo "⚠ 'code' não instalado — pulando config do VS Code (verifique o repo MS em 10-apt-repos.sh / 20-packages.sh)."
  exit 0
fi

# ── Extensions (every provision; install-extension is idempotent) ──
# Extensions live in ~/.vscode/extensions, so install them AS vagrant. One bad
# ID must not abort provisioning, so each install tolerates failure.
fetch_asset vscode/extensions.txt /tmp/vscode-extensions.txt
echo ">> Instalando extensões do VS Code..."
EXT_FLAG=""; [ "$FORCE" == "1" ] && EXT_FLAG="--force"
# `$ext` is deliberately single-quoted: the inner `su` login shell expands it
# per loop iteration, not this provisioning shell. Only `$EXT_FLAG` is spliced
# in from here via the '"…"' break-out.
# shellcheck disable=SC2016
su - vagrant -c '
  while IFS= read -r ext || [ -n "$ext" ]; do
    case "$ext" in ""|\#*) continue ;; esac
    if code --install-extension "$ext" '"$EXT_FLAG"' >/dev/null 2>&1; then
      echo "   ✓ $ext"
    else
      echo "   ✗ $ext (falhou — marketplace inacessível?)"
    fi
  done < /tmp/vscode-extensions.txt
'
rm -f /tmp/vscode-extensions.txt

# ── User settings (first provision only) ──
if [ ! -f /var/lib/vagrant-provisioned ]; then
  echo ">> Semeando settings.json do VS Code (primeiro provisionamento)..."
  fetch_asset vscode/settings.json /home/vagrant/.config/Code/User/settings.json
  chown -R vagrant:vagrant /home/vagrant/.config/Code
else
  echo ">> Já provisionado — preservando o settings.json do VS Code."
fi

# ── Secret storage: persist the GitHub Settings-Sync sign-in ──
# LightDM autologin is passwordless, so gnome-keyring's "login" collection is
# never unlocked and VS Code's sync token lands in the throwaway in-memory
# keyring — lost on every reload, forcing a fresh GitHub sign-in each time.
# Tell Electron to persist secrets in an app-level encrypted file instead
# ("basic" store). Seeded only if argv.json doesn't exist yet — VS Code merges
# its own crash-reporter-id in on first launch, so we never clobber a real one.
# https://github.com/microsoft/vscode/issues/120392
ARGV=/home/vagrant/.vscode/argv.json
if [ ! -e "$ARGV" ]; then
  echo ">> Configurando o password-store do VS Code (basic) para o login do GitHub persistir..."
  install -d -o vagrant -g vagrant /home/vagrant/.vscode
  cat > "$ARGV" <<'ARGVJSON'
// VS Code runtime arguments — Command Palette → "Preferences: Configure Runtime Arguments".
{
	// Persist secrets (GitHub Settings-Sync token, etc.) in an app-level
	// encrypted file instead of the OS keyring — the passwordless autologin
	// session never unlocks gnome-keyring, so the keyring loses the token on
	// every reload. "basic" is the headless/VM-friendly store.
	"password-store": "basic"
}
ARGVJSON
  chown vagrant:vagrant "$ARGV"
fi
