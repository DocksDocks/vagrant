# Build a Debian 13 (Trixie) arm64 UTM box

> **Status: optional / unused by default.** The Apple Silicon path ships on
> `utm/ubuntu-24.04` (see `docs/macos-apple-silicon.md`). Build this **only** if
> you want full Debian-13 parity with the x86_64 box (glibc 2.41, native PHP
> 8.4, the Night Owl XFCE theming, zero Ubuntu-isms). The cost is upkeep: you
> rebuild + re-add the box for OS updates.

There is no published free-provider Debian 13 arm64 box, so you build one with
the `vagrant_utm` author's Packer toolchain (the same one that builds the
`utm/*` boxes). The **builder template lives upstream** in
[`naveenrajm7/utm-box`](https://github.com/naveenrajm7/utm-box) as
`prepare-debian.pkr.hcl`; this folder only supplies the **Trixie image values**
and a helper to pin the checksum, so you don't have to author the builder.

## Prerequisites (macOS Apple Silicon)

```bash
brew install packer utm
vagrant plugin install vagrant_utm
packer plugins install github.com/naveenrajm7/utm
```

## Steps

1. **Clone the upstream template repo:**
   ```bash
   git clone https://github.com/naveenrajm7/utm-box && cd utm-box
   ```

2. **Get the Trixie image checksum** (run the helper in this folder):
   ```bash
   /path/to/this/repo/box/debian-13-arm64/get-image-checksum.sh
   ```
   It prints the canonical SHA512 for the current Debian 13 genericcloud arm64
   image straight from `cloud.debian.org` (no full download needed).

3. **Add a Trixie variables file.** Copy upstream's Debian-12 vars and change
   only the image fields to Trixie (use `debian-13-aarch-cloud.pkrvars.hcl` in
   this folder as the reference for *which* values to set):
   ```bash
   cp os_pkrvars/debian/debian-12-aarch-cloud.pkrvars.hcl \
      os_pkrvars/debian/debian-13-aarch-cloud.pkrvars.hcl
   # edit: iso_url + iso_checksum → Trixie (from step 2), box name → debian-13
   ```
   > Keep the upstream variable **names** — only change the values. The names in
   > `debian-13-aarch-cloud.pkrvars.hcl` here are a guide; reconcile them with the
   > `variable {}` block in upstream `prepare-debian.pkr.hcl` if they differ.

4. **Build** (the `utm-cloud.vm` builder boots the cloud image, applies the
   vagrant contract, and packages a `.box`):
   ```bash
   packer init prepare-debian.pkr.hcl
   packer build -only='utm-cloud.vm' \
     -var-file=os_pkrvars/debian/debian-13-aarch-cloud.pkrvars.hcl \
     prepare-debian.pkr.hcl
   ```
   (Drop the `vagrant-registry`/`artifice` post-processor if you only want a
   local box — you don't need an HCP account for local use.)

5. **Add the box locally and use it** — no Vagrantfile change needed, just the
   env override:
   ```bash
   vagrant box add debian-13-arm64 ./output/*.box
   VAGRANT_ARM_BOX=debian-13-arm64 vagrant up
   ```
   On Trixie the scripts take the Debian path automatically: native PHP 8.4
   (Sury skipped), the full Night Owl XFCE theming runs (41/45 not skipped),
   and `glibc` is 2.41 so `rtk` and friends work.

## Image source

Debian publishes the cloud image at:

```
https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2
https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
```

`latest/` tracks the newest point release. To pin a specific release for
reproducibility, use a dated directory (e.g. `.../trixie/20YYMMDD-NNNN/`) instead
of `latest/` and take its checksum.
