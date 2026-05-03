#!/usr/bin/env bash
# 60-apps-tilix-mousepad.sh — Mousepad (gsettings) + Tilix (dconf load).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

fetch_asset() {
  local rel="$1" dest="$2"
  # Local-dev mode: the repo is mounted at /vagrant on the guest (default shared folder).
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}

# Run gsettings/dconf as vagrant in a one-shot session bus. Three failure modes
# we have to dodge simultaneously:
#
#   1. `dbus-run-session` only uses XDG_RUNTIME_DIR if it can stat() it as a
#      0700 dir owned by the caller; otherwise it silently falls back to
#      /tmp/dbus-XXXXXX, where on bento/debian-13 (Trixie's tmp.mount) an
#      unprivileged daemon spawned through `su -` can fail to bind.
#   2. systemd-logind's user-runtime-dir@$UID.service tmpfs-mounts on top of
#      /run/user/$UID asynchronously. A directory we hand-create with
#      `install -d` works for the first call, then disappears under us on the
#      second/third when logind decides to mount over it. Enable-linger pins
#      the mount for the whole script lifetime so it never races.
#   3. `su -` runs pam_systemd, which caches XDG_RUNTIME_DIR /
#      DBUS_SESSION_BUS_ADDRESS for the session and reuses them on the next
#      `su -` (Red Hat KB 6634751). dbus-run-session only strips
#      DBUS_SESSION_BUS_PID, not the address — so a stale address from the
#      previous gsettings call leaks into the dconf-load call. Use `runuser`
#      (no PAM session setup) and `env -u` to drop the cached address.
loginctl enable-linger vagrant
VAGRANT_UID=$(id -u vagrant)
RUNTIME_DIR="/run/user/${VAGRANT_UID}"
# user-runtime-dir@$UID.service is async; wait up to ~5 s for the tmpfs to land.
for _ in 1 2 3 4 5; do
  [ -d "$RUNTIME_DIR" ] && [ "$(stat -c %u "$RUNTIME_DIR" 2>/dev/null)" = "$VAGRANT_UID" ] && break
  sleep 1
done
# Belt-and-braces: in environments where logind isn't running (containers,
# stripped systemd), fall back to manual creation.
[ -d "$RUNTIME_DIR" ] || install -d -m 0700 -o vagrant -g vagrant "$RUNTIME_DIR"
chmod 1777 /tmp  # last-resort fallback path for dbus-daemon

DBUS_RUN="env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR='$RUNTIME_DIR' dbus-run-session --"

# ── Mousepad: Solarized Dark + Line Numbers ─────────────
runuser -l vagrant -c "$DBUS_RUN gsettings set org.xfce.mousepad.preferences.view show-line-numbers true" || true
runuser -l vagrant -c "$DBUS_RUN gsettings set org.xfce.mousepad.preferences.view color-scheme solarized-dark" || true

# ── Tilix: configuração do terminal ──────────────────────
# Uses dconf directly instead of gsettings to avoid schema compilation issues.
# Tilix identifies profiles by UUID — we set a fixed UUID as the default profile.
fetch_asset tilix.dconf /tmp/tilix.dconf
chown vagrant:vagrant /tmp/tilix.dconf
# Pipe via cat instead of `< /tmp/tilix.dconf` inside the -c string: keeps the
# redirection out of the runuser/dbus-run-session command parser (which can
# misattribute it to dbus-run-session itself rather than dconf).
# No `|| true` here: this is the custom palette + font. Silent failure means
# the user opens Tilix, sees the default ugly theme, and assumes the box is
# broken. Fail loud so a regression is visible in the provision log.
cat /tmp/tilix.dconf | runuser -l vagrant -c "$DBUS_RUN dconf load /com/gexperts/Tilix/"
rm -f /tmp/tilix.dconf

# ── VTE shell integration (silences "Configuration Issue Detected" dialog) ──
# Tilix requires VTE's bash hooks (OSC 7 cwd tracking, prompt markers) sourced
# in interactive shells. Debian ships /etc/profile.d/vte-2.91.sh, but /etc/profile.d
# is only sourced by login shells — Tilix spawns interactive non-login shells, so
# the hooks never load and Tilix flags it. Symlink to the canonical vte.sh path
# and source it from ~/.bashrc when running under VTE.
# https://gnunn1.github.io/tilix-web/manual/vteconfig/
if [[ -f /etc/profile.d/vte-2.91.sh && ! -e /etc/profile.d/vte.sh ]]; then
  ln -s vte-2.91.sh /etc/profile.d/vte.sh
fi
if ! grep -q 'TILIX_ID' /home/vagrant/.bashrc 2>/dev/null; then
  cat >> /home/vagrant/.bashrc <<'BASHRC_VTE'

# VTE shell integration for Tilix (OSC 7 cwd + prompt markers)
if [ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]; then
  . /etc/profile.d/vte.sh
fi
BASHRC_VTE
  chown vagrant:vagrant /home/vagrant/.bashrc
fi
