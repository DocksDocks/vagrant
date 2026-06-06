# macOS Apple Silicon (M1/M2/M3/M4) — install & run

This box runs on Apple Silicon Macs via **UTM** (QEMU on Apple's Hypervisor.framework) instead of VirtualBox. The `Vagrantfile` detects an ARM Mac automatically (`is_mac_arm`) and switches the box + provider — you don't edit anything.

> On **Intel** Macs and Windows/Linux, use VirtualBox instead — see the main [README](../README.md). This guide is **only** for Apple Silicon.

## Why not VirtualBox?

A CPU only runs its own instruction set. Intel/AMD chips speak **x86-64**; Apple Silicon speaks **ARM64**. A hypervisor runs a guest at native speed only when guest and host share the ISA. VirtualBox added an Apple-Silicon build in 7.1+, but it's a developer preview: **ARM guests only, no Vagrant boxes, no Linux Guest Additions** — so it can't run our x86 `bento/debian-13` box or our clipboard/resize stack. UTM (QEMU + Hypervisor.framework) runs ARM64 Linux natively, has a real GUI window, and has a Vagrant provider + ready boxes. Full rationale: [`plans/0009-multi-platform-arm64.md`](../plans/0009-multi-platform-arm64.md).

## What you get

- **Ubuntu 24.04 LTS (arm64)** — the default box (`utm/ubuntu-24.04`).
- **PHP 8.4** — from the `ondrej/php` PPA (Ubuntu 24.04 ships 8.3; the PPA is the same maintainer as Debian's Sury).
- A **functional XFCE desktop** (LightDM autologin) — the bespoke "Night Owl" theming (`41`/`45`) is Debian-only and is **skipped** on Ubuntu, so you get a clean default XFCE.
- All the CLI tooling (Node/pnpm/Claude/Codex, Docker, gh, Composer, ripgrep, superfile, …), same as the Debian box.
- **Chromium** as the browser (Google Chrome has no Linux arm64 build).

### Why Ubuntu 24.04 instead of Debian?

There is **no** free-provider Debian 13 (Trixie) arm64 box, and Debian 12 (Bookworm) is old enough (glibc 2.36) that some modern prebuilt binaries won't run (e.g. `rtk` needs `GLIBC_2.39`). Ubuntu 24.04 is the ready UTM box whose glibc (2.39) is new enough, while staying `apt`-based and compatible with our scripts. If you need true Debian 13 parity, see [Building your own Trixie box](#building-your-own-debian-13-trixie-arm64-box).

## Install (one time)

Everything is via [Homebrew](https://brew.sh):

```bash
brew install --cask vagrant          # the VM tool
brew install --cask utm              # the hypervisor (Apple-native GUI)
vagrant plugin install vagrant_utm   # teaches Vagrant to drive UTM
```

Then **launch UTM once** from Applications so macOS grants it the needed permissions, and quit it.

## Run

```bash
mkdir ~/dev-box && cd ~/dev-box
curl -fsSL https://raw.githubusercontent.com/docksdocks/vagrant/main/Vagrantfile -o Vagrantfile
vagrant up
```

The first `vagrant up` downloads the box, opens a **UTM window**, installs the desktop + tooling (several minutes), then reboots into XFCE with autologin (`vagrant` / `vagrant`).

## Verify it worked

```bash
vagrant ssh
dpkg --print-architecture          # arm64
php -v                             # PHP 8.4.x
which chromium                     # chromium / chromium-browser
systemctl status spice-vdagentd   # active → clipboard/resize working
spf --version                     # superfile runs (arm64 binary)
```

## Day-to-day

```bash
vagrant halt        # shut down
vagrant up          # boot again (fast — no re-provision)
vagrant provision   # re-run provisioning after editing a script/Vagrantfile
vagrant destroy -f  # wipe it
```

## Choosing a different OS / box

The box is overridable with `VAGRANT_ARM_BOX` (no Vagrantfile edit):

```bash
VAGRANT_ARM_BOX=utm/bookworm vagrant up          # Debian 12 (older glibc; PHP via Sury)
VAGRANT_ARM_BOX=my/debian-13-arm64 vagrant up    # your own Trixie box (see below)
```

The scripts detect Debian vs Ubuntu from `/etc/os-release`, so they adapt the Docker/PHP repos and the browser automatically.

## Building your own Debian 13 (Trixie) arm64 box

Only needed if you want full Debian parity (glibc 2.41, native PHP 8.4, the Night Owl theming). A ready-to-follow scaffold lives in [`box/debian-13-arm64/`](../box/debian-13-arm64/) (guide + Trixie image values + a checksum helper); it drives the `vagrant_utm` author's Packer toolchain:

```bash
brew install packer
packer plugins install github.com/naveenrajm7/utm
git clone https://github.com/naveenrajm7/utm-box && cd utm-box
# In the Debian template: swap the Debian 12 genericcloud arm64 image for the
# Debian 13 (Trixie) genericcloud arm64 qcow2 (URL + checksum + release name).
packer build <debian-template>
vagrant box add debian-13-arm64 ./output/*.box
# then:
VAGRANT_ARM_BOX=debian-13-arm64 vagrant up
```

The cost is the upkeep: rebuild/re-publish for OS updates. See `plans/0009-multi-platform-arm64.md` for the trade-off discussion.

## Troubleshooting

- **`No usable default provider` / provider not found** — the plugin isn't installed: `vagrant plugin install vagrant_utm`, and make sure UTM has been opened once.
- **Box not found (`utm/ubuntu-24.04`)** — confirm with `vagrant box add utm/ubuntu-24.04`; if the slug changed, set `VAGRANT_ARM_BOX` to the correct one rather than editing the file.
- **`vagrant up` errors on the `/vagrant` mount** — that's the `directory_share_mode = "virtFS"` line in the Vagrantfile. Normal (GitHub-fetch) provisioning doesn't need `/vagrant`; only local-dev mode (`VAGRANT_SCRIPTS_DIR`) does. You can drop that line if it gives trouble.
- **Clipboard/resize not working** — confirm the VM's display is SPICE in UTM and `systemctl status spice-vdagentd` is active in the guest.
- **A prebuilt binary won't run (`GLIBC_2.xx not found`)** — Ubuntu 24.04 is glibc 2.39; a tool needing newer glibc must run in a container (Docker is installed: use a `debian:trixie`/`ubuntu:25.04` base) or you build the Trixie box above.
- **Chromium feels heavy / slow first launch** — on Ubuntu `chromium-browser` is a snap; first launch seeds snapd. Subsequent launches are normal.
