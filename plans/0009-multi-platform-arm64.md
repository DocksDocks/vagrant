# 0009 — Multi-platform: macOS Apple Silicon (ARM64) via UTM + Ubuntu 24.04 LTS

**Status:** Accepted (merged to `main`)
**Branch:** `claude/vagrantfile-multi-platform-Uif2d` (merged)
**Scope:** `Vagrantfile`, `scripts/10-apt-repos.sh`, `scripts/20-packages.sh`, `scripts/40-xfce-base.sh`, `scripts/41-xfce-theme.sh`, `scripts/45-desktop-extras.sh`, `scripts/65-superfile-fonts.sh`, `scripts/90-claude-config-sync.sh`, `AGENTS.md`, `README.md`, `docs/macos-apple-silicon.md`, `.agents/skills/vagrantfile-orchestrator/SKILL.md`

> **Box pivot (post-testing): Debian 12 Bookworm → Ubuntu 24.04 LTS.** The first cut defaulted the ARM box to `utm/bookworm`, with PHP 8.4 from Sury. Real provisioning surfaced Bookworm's age: its **glibc 2.36** can't run modern prebuilt binaries — `rtk` (from the config-sync step) needs **`GLIBC_2.39`** and aborted. Rather than build a Debian 13 box, the default moved to **`utm/ubuntu-24.04`** (glibc **2.39**, PHP 8.4 via `ppa:ondrej/php`), the most modern *ready* UTM box that's still `apt`-based. Scripts are now Debian-*and*-Ubuntu aware (`/etc/os-release`), and `VAGRANT_ARM_BOX` still selects `utm/bookworm` or a self-built Trixie box. The Bookworm rationale below is retained for context.

## Problem

The box only provisions on x86_64 hosts running VirtualBox. On **macOS Apple Silicon (M1–M4)** `vagrant up` cannot work at all:

- VirtualBox has no Apple Silicon build, so the entire `config.vm.provider "virtualbox"` block and the `bento/debian-13` box (amd64-only) are unusable.
- Even with a different provider, several provisioning scripts hard-abort on arm64: `google-chrome-stable` has no Linux ARM64 build (kills the `20-packages.sh` batch under `set -euo pipefail`), and the VirtualBox Guest Additions / clipboard / auto-resize scripts (`30`/`50`/`51`) have nothing to talk to.

The maintainer develops on an Apple Silicon Mac and needs a working desktop dev box there, **with PHP 8.4** (a hard project requirement).

## Root cause

Three independent constraints collide on Apple Silicon:

1. **No VirtualBox on ARM.** Oracle ships no aarch64 build; VirtualBox is x86-only. A different hypervisor/provider is mandatory.
2. **No free-provider Debian 13 Trixie arm64 box.** `bento/debian-13` is amd64-only ([chef/bento#1545](https://github.com/chef/bento/issues/1545) — many ARM64 boxes are missing). The Debian Cloud Team publishes Trixie for libvirt only ([Debian bug #1110834](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1110834)). The only maintained Trixie aarch64 Vagrant box ([`defanator/debian-13`](https://github.com/defanator/vagrant-boxes)) is **VMware-only**. The ready arm64 boxes for free providers are Debian **12 Bookworm** (`utm/bookworm`, `perk/debian-12-arm64`).
3. **The free QEMU-native Vagrant provider is headless.** [`vagrant-qemu`](https://github.com/ppggff/vagrant-qemu) runs QEMU with `-display none` — no GUI window. This box is a full XFCE/LightDM/Tilix **desktop**, so a headless provider throws away the entire desktop layer. [UTM](https://mac.getutm.app/) (QEMU front-end on Apple's Hypervisor.framework) gives a native GUI window and has a community Vagrant provider, [`vagrant_utm`](https://github.com/naveenrajm7/vagrant_utm).

Consequence of picking Bookworm: it ships **PHP 8.2**, but the project requires **8.4**. The [Sury repo](https://deb.sury.org/) (`deb.sury.org`, Ondřej Surý) publishes `php8.4-*` for Bookworm on **arm64** as well as amd64 — including every extension we use (cli, curl, mbstring, xml, zip, bcmath, intl). Only niche extensions (e.g. `swoole`) lag on arm64, and we use none of them.

## Decision

Keep a **single conditional Vagrantfile**. Detect the host once:

```ruby
is_mac_arm = RUBY_PLATFORM.include?("darwin") && RbConfig::CONFIG["host_cpu"].include?("arm64")
ARM_BOX = ENV.fetch("VAGRANT_ARM_BOX", "utm/bookworm")
```

and branch box + provider + script selection on it:

- **Box:** `is_mac_arm ? ARM_BOX : "bento/debian-13"` (default `utm/bookworm`, overridable via `VAGRANT_ARM_BOX` for a self-built Trixie arm64 image).
- **Provider:** `if is_mac_arm` → `config.vm.provider "utm"` (`name`/`memory`/`cpus`/`directory_share_mode = "virtFS"`); `else` → the unchanged VirtualBox block.
- **Scripts:** `VBOX_ONLY_SCRIPTS = %w[30-guest-additions 50-vboxclient-supervisor 51-vbox-autoresize]` are skipped on Apple Silicon (`next if is_mac_arm && VBOX_ONLY_SCRIPTS.include?(name)`).

The per-concern scripts become **guest-arch-aware** via `dpkg --print-architecture` (and codename-aware for PHP), so the same scripts serve both boxes:

- **PHP 8.4 pinned on both arches.** Drop the floating `php-*` metapackages; install explicit `php8.4-*` (native on Trixie, Sury on Bookworm). Sury added only on `bullseye|bookworm`.
- **Browser by arch.** Chrome on amd64; Chromium on arm64 (Chrome has no Linux arm64 build). The Chrome no-GPU policy stays amd64-only (it's Chrome/VMSVGA-specific).
- **Guest integration by arch.** arm64 installs `spice-vdagent` + `qemu-guest-agent` (UTM clipboard/resize/clean-shutdown) in place of the skipped VBox helpers.
- **superfile by arch.** Download the binary matching `dpkg --print-architecture` instead of hardcoding `-amd64`.

The x86_64 / VirtualBox / Trixie path is unchanged.

## Alternatives considered

| Option | Why rejected |
|---|---|
| `vagrant-qemu` provider | Headless (`-display none`) — drops the entire XFCE desktop the box exists to provide. Fine only for SSH/VS Code-Remote use. |
| VMware Fusion (`vmware_desktop`) + `defanator/debian-13` (Trixie!) | Genuinely viable and keeps Debian 13 parity — VMware Fusion is free since Nov 2024. Rejected because the maintainer chose UTM (the Broadcom download portal was a blocker). Still the path if Trixie parity on ARM ever becomes mandatory. |
| `perk/debian-12-arm64` on `vagrant-qemu` | Bookworm box exists, but provider is headless (same as above). |
| Stay on Debian 13 by building our own Trixie arm64 box (Packer/fai) | Most effort + ongoing maintenance (rebuild/host/update). Deferred; `VAGRANT_ARM_BOX` leaves the door open. |
| Debian 14 Forky arm64 | Forky is in *testing*, final release ~2027, no Vagrant box, and `testing` auto-removes packages (the exact reason we already avoid `debian/testing64`). |
| Drop to Debian 12 PHP 8.2 on ARM | PHP 8.4 is a hard requirement; non-starter. |
| Split into per-target folders (`envs/trixie-x86`, `envs/bookworm-arm`) + shared scripts | Maintainer chose a single conditional Vagrantfile — one source of truth, fewer moving parts. The remote-fetch design already makes scripts "shared" without folders. |
| Parallels (`vagrant-parallels`) | Paid. |

## How it's enabled at provision time

- **`Vagrantfile`** (top): `is_mac_arm` + `ARM_BOX` constants. **`VBOX_ONLY_SCRIPTS`** constant near the `SCRIPTS` array. Inside `Vagrant.configure`: the `config.vm.box` ternary, the `if is_mac_arm` provider branch (UTM vs VirtualBox), and the `next if is_mac_arm && VBOX_ONLY_SCRIPTS.include?(name)` guard at the top of the `SCRIPTS.each` loop. `is_mac_arm` is a top-level local captured by the `Vagrant.configure` block closure (works because top-level locals are visible to later blocks in the same file).
- **`scripts/10-apt-repos.sh`**: Chrome apt repo gated to `amd64`; on `bullseye|bookworm` the Sury repo is added via the official `debsuryorg-archive-keyring.deb` keyring package (avoids the recurring `apt.gpg` BADSIG / "Splitting up InRelease … failed" errors) → `signed-by=/usr/share/keyrings/deb.sury.org-php.gpg`.
- **`scripts/20-packages.sh`**: `php-*` metas removed from the batch; explicit `php8.4-cli/common/curl/mbstring/xml/zip/bcmath/intl` installed before Composer; arch branch installs `google-chrome-stable` (amd64, + dedup of `google-chrome.sources`) or `chromium spice-vdagent qemu-guest-agent` (arm64).
- **`scripts/40-xfce-base.sh`**: `BROWSER_DESKTOP`/`BROWSER_HELPER` chosen by arch; docklike pin + mimeapps + exo-web-browser `sed`-substituted to the right `.desktop`; a Chromium XFCE helper written on arm64; Chrome no-GPU policy gated to amd64.
- **`scripts/65-superfile-fonts.sh`**: `SPF_DIRNAME="superfile-linux-v${SPF_VERSION}-$(dpkg --print-architecture)"`.

Host prerequisites on Apple Silicon: `brew install --cask utm` and `vagrant plugin install vagrant_utm`.

## Verification

On an Apple Silicon Mac (the new path):

1. `vagrant plugin list` shows `vagrant_utm`; UTM is installed.
2. `vagrant up` selects the `utm` provider, downloads `utm/bookworm`, opens a **GUI window**, and provisions to completion (no `set -e` abort — the Chrome batch failure is gone).
3. In the guest:
   ```
   dpkg --print-architecture          # arm64
   php -v                             # PHP 8.4.x
   apt-cache policy php8.4-cli        # candidate from packages.sury.org
   which chromium                     # /usr/bin/chromium
   systemctl status spice-vdagentd   # active → clipboard/resize path live
   spf --version                     # runs (arm64 binary, not exec-format-error)
   ```
4. Desktop comes up (LightDM autologin → XFCE), host↔guest clipboard works via SPICE, window resize reflows.
5. `vagrant up VM_PROFILE=2` etc. still works (resource menu unaffected by arch).

On x86_64 (no regression):

6. `vagrant up` on Windows/Linux/Intel Mac still uses VirtualBox + `bento/debian-13`; `php -v` is 8.4 (native Trixie, Sury skipped — confirm no `sury-php.list` in `/etc/apt/sources.list.d/`); Chrome installed; `30`/`50`/`51` all run.
7. `ruby -c Vagrantfile` → Syntax OK; `bash -n scripts/*.sh` clean.

## Files changed

- `Vagrantfile` — `is_mac_arm`/`ARM_BOX` detection, `VBOX_ONLY_SCRIPTS`, conditional box + UTM/VirtualBox provider blocks, per-script skip guard.
- `scripts/10-apt-repos.sh` — Chrome repo amd64-gated; Sury PHP repo on bullseye/bookworm (keyring-deb method).
- `scripts/20-packages.sh` — explicit `php8.4-*`; arch-conditional browser + SPICE/QEMU guest agents.
- `scripts/40-xfce-base.sh` — browser-by-arch (Chrome/Chromium) across dock/helper/mimeapps/exo; no-GPU policy amd64-only.
- `scripts/65-superfile-fonts.sh` — arch-aware superfile download.
- `AGENTS.md` — multi-platform overview, base-box/hypervisor bullets, script descriptions, Apple Silicon Common Issues entry.
- `.agents/skills/vagrantfile-orchestrator/SKILL.md` — base-box constraint scoped to x86_64 + new ARM/UTM constraint; description + `metadata.updated` + `source_files` refreshed.

No new tracked secrets (pre-flight: no keys/tokens/PATs added; only the existing intentional `vagrant:vagrant` password). New host-side dependency: the `vagrant_utm` plugin + UTM (documented, not vendored).
