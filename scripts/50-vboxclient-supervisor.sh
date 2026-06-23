#!/usr/bin/env bash
# 50-vboxclient-supervisor.sh — supervise VBoxClient --clipboard / --draganddrop
# via systemd --user (upstream helpers terminate silently on X events; see
# VirtualBox #5266/#6150, NixOS/nixpkgs#65542). See plans/0001-clipboard-supervisor.md.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

mkdir -p /home/vagrant/.config/autostart \
         /home/vagrant/.config/systemd/user \
         /home/vagrant/.config/systemd/user/default.target.wants \
         /home/vagrant/.config/systemd/user/timers.target.wants \
         /home/vagrant/.local/bin

# Remove the pre-fix VBoxClient-all autostart (superseded by supervised units)
rm -f /home/vagrant/.config/autostart/vboxclient-all.desktop

# Disable Oracle's /etc/X11/Xsession.d/98vboxadd-xclient so it stops pre-launching
# `VBoxClient --clipboard` and `VBoxClient --draganddrop` at X login. Those processes
# claim the X11 VBOXCLIENT_STARTED atom and prevent the supervised systemd units
# below from ever taking over (symptom: vbox-clipboard.service stuck in
# Restart=always loop with "service already running, exitting"). vboxclient-session.desktop
# already handles --vmsvga / --seamless / --display, so Oracle's Xsession.d helper
# is fully redundant. dpkg-divert keeps the override across virtualbox-guest-utils
# upgrades. See plans/0003-vboxclient-xsession-divert.md.
if [ -f /etc/X11/Xsession.d/98vboxadd-xclient ] && \
   ! dpkg-divert --list /etc/X11/Xsession.d/98vboxadd-xclient 2>/dev/null \
       | grep -q '98vboxadd-xclient\.disabled'; then
  dpkg-divert --add --rename --quiet \
    --divert /etc/X11/Xsession.d/98vboxadd-xclient.disabled \
    /etc/X11/Xsession.d/98vboxadd-xclient
fi

fetch_asset systemd/vbox-clipboard.service   /home/vagrant/.config/systemd/user/vbox-clipboard.service
fetch_asset systemd/vbox-draganddrop.service /home/vagrant/.config/systemd/user/vbox-draganddrop.service

# Optional post-unlock watchdog: kicks the supervised clipboard helper on
# screen-unlock (XFCE/freedesktop ScreenSaver ActiveChanged=false). Belt-and-
# braces on top of Restart=always — only matters if the user re-enables screen
# locking. See Oracle VBox #5266 / #19234.
fetch_asset vbox-clipboard-unlock-watchdog.sh /home/vagrant/.local/bin/vbox-clipboard-unlock-watchdog
chmod 0755 /home/vagrant/.local/bin/vbox-clipboard-unlock-watchdog
fetch_asset systemd/vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/vbox-clipboard-unlock-watchdog.service

# Periodic healthcheck timer: catches the same bug without needing a lock
# event. The watchdog above only fires on D-Bus ScreenSaver ActiveChanged,
# and on this box light-locker is shadowed (Hidden=true) so that signal
# never arrives — leaving a silently-broken HGCM<->X11 bridge sitting
# broken forever. The timer scans the clipboard unit's own journal every
# 2 min for the degraded-bridge signature (formats 'NONE' or to 'INVALID')
# and restarts on hit. See plans/0004.
fetch_asset vbox-clipboard-healthcheck.sh /home/vagrant/.local/bin/vbox-clipboard-healthcheck
chmod 0755 /home/vagrant/.local/bin/vbox-clipboard-healthcheck
fetch_asset systemd/vbox-clipboard-healthcheck.service \
  /home/vagrant/.config/systemd/user/vbox-clipboard-healthcheck.service
fetch_asset systemd/vbox-clipboard-healthcheck.timer \
  /home/vagrant/.config/systemd/user/vbox-clipboard-healthcheck.timer

# Real-time bridge watcher: tails the clipboard unit's journal (-n0, new lines
# only) and restarts within ~1s of the degraded-bridge signature, instead of
# waiting up to 2 min for the healthcheck timer above. The timer's read-probe
# stays as the proactive (no-paste-needed) detector + stateless backstop.
# See plans/0012.
fetch_asset vbox-clipboard-bridge-watcher.sh /home/vagrant/.local/bin/vbox-clipboard-bridge-watcher
chmod 0755 /home/vagrant/.local/bin/vbox-clipboard-bridge-watcher
fetch_asset systemd/vbox-clipboard-bridge-watcher.service \
  /home/vagrant/.config/systemd/user/vbox-clipboard-bridge-watcher.service

# Enable the user units by creating the WantedBy symlinks directly
# (avoids needing XDG_RUNTIME_DIR / an active user manager during provision)
ln -sf ../vbox-clipboard.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard.service
ln -sf ../vbox-draganddrop.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-draganddrop.service
ln -sf ../vbox-clipboard-unlock-watchdog.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard-unlock-watchdog.service
ln -sf ../vbox-clipboard-bridge-watcher.service \
  /home/vagrant/.config/systemd/user/default.target.wants/vbox-clipboard-bridge-watcher.service
ln -sf ../vbox-clipboard-healthcheck.timer \
  /home/vagrant/.config/systemd/user/timers.target.wants/vbox-clipboard-healthcheck.timer

# XDG autostart: import DISPLAY/XAUTHORITY into the user manager, ensure
# the supervised services are running for this session, and launch the
# one-shot helpers that don't need supervision.
fetch_asset vboxclient-session.desktop /home/vagrant/.config/autostart/vboxclient-session.desktop

# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.
