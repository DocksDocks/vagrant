#!/usr/bin/env bash
# get-image-checksum.sh — print the canonical SHA512 for the Debian 13 (Trixie)
# genericcloud arm64 cloud image, for pinning in the Packer pkrvars file.
#
# Reads the official SHA512SUMS published next to the image on cloud.debian.org,
# so it's the upstream-signed value (no multi-GB download needed). Pass a dated
# release dir as $1 to pin a specific point release instead of "latest".
#
#   ./get-image-checksum.sh                 # latest Trixie
#   ./get-image-checksum.sh 20260301-2050   # a specific release
set -euo pipefail

REL="${1:-latest}"
BASE="https://cloud.debian.org/images/cloud/trixie/${REL}"
IMG="debian-13-genericcloud-arm64.qcow2"

echo ">> Fetching SHA512SUMS from ${BASE}/ ..." >&2
sum=$(curl -fsSL "${BASE}/SHA512SUMS" | awk -v img="$IMG" '$2 == img {print $1}')

if [ -z "$sum" ]; then
  echo "✗ Could not find a checksum for ${IMG} at ${BASE}/SHA512SUMS" >&2
  echo "  Check the release dir exists and lists the arm64 genericcloud image." >&2
  exit 1
fi

echo "" >&2
echo "  Image : ${BASE}/${IMG}" >&2
echo "  Paste into the Packer pkrvars file:" >&2
echo "" >&2
echo "iso_url      = \"${BASE}/${IMG}\""
echo "iso_checksum = \"sha512:${sum}\""
