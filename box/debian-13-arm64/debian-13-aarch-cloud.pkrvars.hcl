# Debian 13 (Trixie) arm64 — Packer variables for naveenrajm7/utm-box's
# prepare-debian.pkr.hcl (the `utm-cloud.vm` builder).
#
# HOW TO USE: copy upstream's os_pkrvars/debian/debian-12-aarch-cloud.pkrvars.hcl
# into the utm-box repo, then change ONLY the image + name fields to the values
# below. Keep every other variable from upstream as-is. The names here mirror the
# usual utm-box scheme; if upstream's `variable {}` block differs, defer to it.
#
# Get a current, upstream-signed checksum with:  ./get-image-checksum.sh
# (then replace iso_url/iso_checksum below with what it prints).

# ── Image (Debian 13 Trixie genericcloud, aarch64) ──────
iso_url      = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2"
iso_checksum = "sha512:REPLACE_ME"   # ← run get-image-checksum.sh and paste

# ── Box identity / metadata ─────────────────────────────
box_basename = "debian-13"
os_name      = "debian"
os_version   = "13"
arch         = "aarch64"

# ── VM resources (build-time; the Vagrantfile reallocates at `vagrant up`) ──
cpus      = 2
memory    = 2048
disk_size = 20480
