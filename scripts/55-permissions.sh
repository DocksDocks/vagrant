#!/usr/bin/env bash
# 55-permissions.sh — ownership pass for /home/vagrant, run between the
# system-config phase (40, 41, 50, 51) and the user-tool-install phase
# (60, 65, 70, 80, 85, 90).
#
# Earlier scripts run as root (Vagrant's shell provisioner) and `mkdir -p`
# directories under /home/vagrant/{.config,.local,...} as root. Later scripts
# `su - vagrant -c '…'` and try to write new files into those directories;
# without this sweep, they hit EACCES (Claude installer's mkdir
# ~/.local/share/claude, sync.sh's mv ~/.local/bin/rtk, git reading
# ~/.config/git/{ignore,attributes}, …). Rather than make each upstream
# script chown its own outputs (and possibly miss files written by sub-tools),
# this catch-all recursively chowns the entire home directory to vagrant.
#
# Why position 55 and not 95: the consumers above run at 60–90, so the sweep
# must precede them. No script after 55 creates root-owned directories under
# /home/vagrant — file append (`cat >> ~/.bashrc`) preserves the existing
# owner, and 60+ use `su - vagrant -c` / `runuser` / `install -d -o vagrant`.
#
# `chown -R` only changes ownership, not modes — files that are 0600 (e.g.
# ~/.ssh/id_ed25519, ~/.config/secrets.env) keep their tight perms. Files
# already vagrant-owned get a no-op chown.
set -euo pipefail

chown -R vagrant:vagrant /home/vagrant
