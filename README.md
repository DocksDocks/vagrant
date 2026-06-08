# Debian 13 Dev Box

> 🇧🇷 Em português: [README.pt-BR.md](./README.pt-BR.md)

A complete development VM running Debian 13 (Trixie), provisioned automatically by Vagrant. Debian is lighter than Ubuntu (~180 MB base RAM vs ~400 MB), uses `apt` the same way, and stays compatible with every common dev tool.

## Prerequisites

The hypervisor depends on your machine. Pick **one** track, then run `vagrant up` — the `Vagrantfile` auto-detects the host and selects the right box/provider.

### Track A — Windows, Linux, or Intel Mac (x86_64)

1. **VirtualBox** — the hypervisor that runs the VM. Download: https://www.virtualbox.org/wiki/Downloads
2. **Vagrant** — creates/configures the VM from `Vagrantfile`. Download: https://developer.hashicorp.com/vagrant/install

You get **Debian 13 (Trixie)** with the full Night Owl XFCE desktop. Restart your terminal after installing so `vagrant` and `VBoxManage` are on `PATH`.

### Track B — macOS Apple Silicon (M1/M2/M3/M4)

VirtualBox can't run our x86 box on Apple Silicon, so this track uses **UTM** (QEMU + Apple's Hypervisor.framework). Everything installs via [Homebrew](https://brew.sh):

```bash
brew install --cask vagrant      # the VM tool
brew install --cask utm          # the hypervisor (GUI, Apple-native)
vagrant plugin install vagrant_utm   # teaches Vagrant to drive UTM
```

Then **open UTM once** (from Applications) so macOS grants it permission, and quit it. That's it — no VirtualBox.

You get **Ubuntu 24.04 LTS (arm64)** with a functional XFCE desktop (the Night Owl theming is Debian-only and is skipped here), **PHP 8.4** (via the `ondrej/php` PPA), and all the CLI tooling. Ubuntu 24.04 is used because there's no free Debian 13 arm64 box and its modern glibc (2.39) runs recent prebuilt binaries that Debian 12 can't.

> **Override the box** (optional): `VAGRANT_ARM_BOX=utm/bookworm vagrant up` for Debian 12, or point it at your own Debian 13 Trixie arm64 box. See [docs/macos-apple-silicon.md](./docs/macos-apple-silicon.md) for the full rationale, the UTM box-building path, and troubleshooting.

## What's installed

| Tool             | Notes                                                            |
|------------------|------------------------------------------------------------------|
| **XFCE 4**       | Lightweight desktop with LightDM autologin (no goodies bloat)    |
| **Google Chrome / Chromium** | Chrome on x86_64 (official Google repo); Chromium on Apple Silicon (no Chrome arm64 build) |
| **Git**          | From the Debian repository                                       |
| **GitHub CLI**   | `gh` — PRs, issues, repo ops from the terminal                   |
| **Python 3**     | With `pip` and `venv`                                            |
| **PHP**          | CLI + common extensions (curl, mbstring, xml, zip, bcmath, intl) |
| **Composer**     | PHP dependency manager (SHA-384 verified at install)             |
| **Docker**       | Engine + CLI + Buildx + Compose v2 (plugin, no hyphen)           |
| **Node.js LTS**  | Via `nvm` — always installs the current LTS                      |
| **npm**          | Bundled with Node                                                |
| **pnpm**         | Globally installed via npm                                       |
| **Claude Code**  | Anthropic's native CLI                                           |
| **Codex CLI**    | OpenAI's native CLI, globally installed via npm                  |
| **ShellCheck**   | Linter for shell scripts                                         |
| **jq**           | JSON processor for the terminal                                  |
| **yq**           | YAML processor for the terminal                                  |
| **ripgrep**      | Ultra-fast code search (`rg`)                                    |
| **build-essential** | gcc, make, headers — native extension compilation             |
| **Tilix**        | Split-pane terminal (replaces tmux with a GUI)                   |
| **VS Code**      | `code` (Microsoft repo); Night Owl theme + settings/extensions seeded |
| **fzf**          | Fuzzy finder for the terminal                                    |
| **bat**          | `cat` with syntax highlighting (alias `bat` → `batcat`)          |
| **fd-find**      | Fast file finder (alias `fd` → `fdfind`)                         |
| **htop / btop**  | Process monitors                                                 |
| **tree**         | Directory tree visualization                                     |
| **direnv**       | Per-project environment variables                                |
| **git-pull-all** | Bulk-update every repo under a dir (`git pull-all` works too)     |
| **superfile**    | TUI file manager (`spf`) with Nerd Font icons                    |

## VM resources (interactive profile menu)

On `vagrant up`/`reload` in an interactive terminal, the Vagrantfile detects host RAM/CPUs and shows a **5-tier resource menu**. Move with ↑/↓ (or `j`/`k`, or press `1`–`5`), confirm with **Enter**, cancel with `q`/Esc. Your choice is remembered in `.vagrant/last_profile` and pre-selected next time.

Every tier is **capped at 75% of host RAM and CPUs**, and RAM is always a **whole number of GB** — fractional sizes like 6.5 GB are flaky on VirtualBox/UTM and can keep the VM from starting. On a 16 GB / 8-core host the ladder is:

| Tier | RAM   | vCPU | Notes      |
|------|-------|------|------------|
| 1    | 4 GB  | 4    |            |
| 2    | 6 GB  | 5    | default    |
| 3    | 8 GB  | 6    |            |
| 4    | 10 GB | 6    |            |
| 5    | 12 GB | 6    | = 75% cap  |

The same percentages scale to any host (e.g. 32 GB / 16 cores → 8 / 12 / 16 / 20 / 24 GB; 8 GB / 4 cores → 2 / 3 / 4 / 5 / 6 GB). VRAM is fixed at 256 MB (the VMSVGA framebuffer ceiling — unrelated to system RAM).

- **Non-interactive** runs (CI, `vagrant ssh`/`status`/`provision`, piped stdin) skip the menu and use the remembered tier, or tier 2 by default.
- **Skip the menu once** with `VM_PROFILE=1..5 vagrant up` (doesn't change the saved choice).

Works on Windows, macOS, and Linux — the menu reads arrow keys on the classic Windows console too.

## Extras configured automatically

- **XFCE desktop** with autologin — `vagrant up` opens directly to the desktop, no password prompt.
- **Single bottom panel** — whiskermenu (left), centered dock with Docklike (pinned app icons that also show open windows, like Ubuntu's dock), systray and clock (right). No top bar.
- **Pinned dock apps** — Chrome, Thunar, Tilix, VS Code ready with one click. Open apps merge into their dock icon.
- **Tokyo Night GTK theme** (`Tokyonight-Dark`, the closest maintained navy match to Night Owl) + **Papirus-Dark icons** + **Noto Sans font** + **DMZ-White cursor** — a clean modern dark look. Compositor enabled under VMSVGA.
- **Ubuntu-style screenshots** — press **PrtSc** to drag-select a region; it's auto-saved to `~/Pictures/Screenshots` and copied to the clipboard in one go, no chooser or save dialog. (Shift+PrtSc still does a region capture with the save dialog; Alt+PrtSc grabs the active window.)
- **Downloads and Pictures pinned** in the Thunar sidebar (file-manager Places).
- **Bidirectional clipboard and drag-and-drop** between host and VM (supervised systemd user units; survives X-event storms).
- **Google Chrome** pre-installed for in-VM browsing, with hardware-acceleration disabled via managed policy (avoids Chrome's deadlock under VMSVGA).
- **ED25519 SSH key** generated at `~/.ssh/id_ed25519` — public key is printed at the end of provisioning so you can paste it into GitHub/GitLab.
- **`~/projects`** — directory for your projects, pre-created.
- **`git-pull-all`** — fetch + fast-forward every repo under a directory tree (defaults to the current dir). Run `git-pull-all ~/projects` to update them all at once; dirty, diverged, or upstream-less repos are fetched but never force-pulled, and reported at the end. Repos are updated concurrently (default 8 at a time, `-j N` to tune, `-j1` for serial) — on ~16 repos that's roughly 7× faster than one-by-one. Use `-f`/`--fetch-only` to fetch without pulling. `git pull-all` dispatches to the same command.
- **Aliases** — `pf` (~/projects), `fd` (fdfind), `bat` (batcat).
- **Docker without sudo** — the `vagrant` user is in the `docker` group.
- **direnv** — hook installed in `.bashrc` so `.envrc` files load automatically.
- **Tilix** with 4% transparency as the default dock terminal.
- **VS Code** with the Night Owl theme and Material icons; the maintainer's `settings.json` and extension set are seeded on the first provision (your in-VM edits are preserved on re-provision). The GitHub Settings-Sync sign-in persists across reloads (`password-store: basic`).
- **Audio enabled** — output via Intel HD Audio (no microphone).
- **`vagrant` user password**: `vagrant` (set on the first provision only; change it freely afterward — re-provisioning won't reset it).
- **Git config** — `init.defaultBranch=main`. The placeholder `user.name` / `user.email` are only set if you haven't configured your own — re-running `vagrant provision` won't overwrite your real identity.
- **Agent config sync** — `.claude` and `.codex` config synced from the SSOT repo (`DocksDocks/public`) on first provision.
- **Timezone** — `America/Sao_Paulo` (UTC-3).
- **`~/.config/secrets.env`** — 0600 placeholder file sourced from `~/.bashrc`. Drop sensitive `export` lines (API keys, OAuth tokens) here instead of polluting `~/.bashrc`.

## First use (after provisioning)

After the first `vagrant up`, set your Git identity and authenticate with GitHub:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
gh auth login
```

The finalize banner will only nag you about whichever of these still need to be done.

## Common commands

### Boot the VM for the first time

```bash
vagrant up
```

On the first run, Vagrant downloads the base image, creates the VM, and runs all of provisioning (package install + XFCE setup). This takes a few minutes depending on your connection. The VM auto-reboots after provisioning and lands you in the XFCE desktop with autologin as `vagrant`.

> On **Apple Silicon Macs** this uses UTM + Ubuntu 24.04 instead of VirtualBox + Debian 13 — see [docs/macos-apple-silicon.md](./docs/macos-apple-silicon.md).

### SSH into the VM

```bash
vagrant ssh
```

You log in as `vagrant`. Every tool (node, docker, pnpm, claude, codex, etc.) is on `PATH`.

### Shut down the VM

```bash
vagrant halt
```

Cleanly powers off, preserving disk state. The next `vagrant up` boots in seconds without re-provisioning.

### Re-provision (re-run the install scripts)

```bash
vagrant provision
```

Useful when you've edited the Vagrantfile or a `scripts/*.sh` and want to apply changes without destroying the VM. The scripts are idempotent — re-running won't duplicate config. Force a full reinstall of the components that cache themselves (Guest Additions, Nerd Font, superfile, nvm, Node, pnpm, Codex CLI, Claude Code) with:

```bash
FORCE_REINSTALL=1 vagrant provision
```

### Destroy the VM completely

```bash
vagrant destroy
```

Removes the VM and its virtual disk. Run when you want a clean slate. The next `vagrant up` rebuilds and re-provisions everything.

### Status

```bash
vagrant status
```

### Suspend / resume

```bash
vagrant suspend   # save state to RAM (like hibernate)
vagrant resume    # pick up where you left off
```

## Forwarded ports

To access services running in the VM from your host browser, uncomment or add `forwarded_port` lines in the `Vagrantfile`:

```ruby
config.vm.network "forwarded_port", guest: 3000, host: 3000
config.vm.network "forwarded_port", guest: 8080, host: 8080
```

Then run `vagrant reload` to apply.

## Repository layout

```
.
├── Vagrantfile         # host detection, VM config, registers per-concern provisioners
├── scripts/            # numbered shell scripts, run from the clone (or fetched from GitHub)
│   ├── _lib.sh         # shared helpers (fetch_asset)
│   ├── 10-apt-repos.sh
│   ├── 15-grub-quickboot.sh
│   ├── 20-packages.sh
│   ├── 30-guest-additions.sh
│   ├── 40-xfce-base.sh
│   ├── 41-xfce-theme.sh
│   ├── 45-desktop-extras.sh
│   ├── 50-vboxclient-supervisor.sh
│   ├── 51-vbox-autoresize.sh
│   ├── 55-permissions.sh
│   ├── 60-tilix.sh
│   ├── 65-superfile-fonts.sh
│   ├── 66-vscode.sh
│   ├── 70-nodejs-claude.sh
│   ├── 80-git-ssh.sh
│   ├── 85-secrets-env.sh
│   ├── 90-claude-config-sync.sh
│   └── 99-finalize.sh
├── assets/             # XFCE/Tilix/Chrome configs, systemd units, helper scripts
├── plans/              # design docs (clipboard supervisor, Vagrantfile split)
├── CLAUDE.md           # technical context for Claude Code sessions
├── README.md           # this file
└── README.pt-BR.md     # Portuguese version
```

## Adding a new tool

1. **Plain apt package** — append it to the `apt-get install` list in `scripts/20-packages.sh` and run `vagrant provision`.
2. **Custom install (curl + tar, GitHub release, etc.)** — create a new numbered script in `scripts/` (pick a number that reflects execution order, e.g. `75-mytool.sh`), add the name to the `SCRIPTS` array in `Vagrantfile`, and run `vagrant provision`.
3. **Static config (XML, JSON, systemd unit)** — drop the file in `assets/` and use the shared `fetch_asset` helper from `scripts/_lib.sh` inside whichever script applies the config.

Every script begins with `set -euo pipefail`, so any unhandled error aborts provisioning. Commands that may fail legitimately (e.g. `gsettings`, `dconf`) use `|| true`. To force reinstall of the components that cache themselves (Guest Additions, Nerd Font, superfile, nvm, Node, pnpm, Codex CLI, Claude Code), run `FORCE_REINSTALL=1 vagrant provision`.
