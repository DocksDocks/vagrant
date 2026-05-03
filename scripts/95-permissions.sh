#!/usr/bin/env bash
# 95-permissions.sh — final ownership pass for /home/vagrant.
#
# Earlier scripts run as root (Vagrant's shell provisioner) and write into
# /home/vagrant/{.config,.local,.bashrc,...}. Instead of each script chowning
# its own outputs (and possibly missing files written by sub-tools), this
# catch-all runs once at the end of the SCRIPTS list and recursively chowns
# the entire home directory to vagrant.
#
# `chown -R` only changes ownership, not modes — files that were 0600 (e.g.
# ~/.ssh/id_ed25519, ~/.config/secrets.env) keep their tight perms. Files
# already vagrant-owned (e.g. anything written via `su - vagrant -c …`) get
# a no-op chown.
set -euo pipefail

chown -R vagrant:vagrant /home/vagrant
