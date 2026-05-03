#!/usr/bin/env bash
# _lib.sh — shared helpers for vagrant provisioning scripts.
#
# Sourced by each script via $VAGRANT_LIB_PATH (set by the Vagrantfile inline
# runner) so the same fetch logic doesn't need to be duplicated 6× across
# numbered scripts. Not directly executed.
#
# Conventions:
#   - SCRIPTS_REPO / SCRIPTS_REF — set by Vagrantfile env, point at the upstream
#     copy on raw.githubusercontent.com.
#   - VAGRANT_SCRIPTS_DIR — set when running in local-dev mode (the repo is
#     mounted at /vagrant on the guest).
#
# Add new shared helpers here when a pattern repeats across 2+ scripts.

# fetch_asset REL DEST
#
# Place a static config / asset file at DEST. In local-dev mode, copies from
# /vagrant/assets/REL. Otherwise curls it from raw.githubusercontent.com at
# the configured ref.
fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}
