# Debian 13 Dev Box

> 🇧🇷 Em português: [README.pt-BR.md](./README.pt-BR.md)

A complete development VM running Debian 13 (Trixie), provisioned automatically by Vagrant. Debian is lighter than Ubuntu (~180 MB base RAM vs ~400 MB), uses `apt` the same way, and stays compatible with every common dev tool.

## Prerequisites

Install both before you start:

1. **VirtualBox** — the hypervisor that runs the VM under the hood.
   Download: https://www.virtualbox.org/wiki/Downloads

2. **Vagrant** — the tool that creates and configures the VM from `Vagrantfile`.
   Download: https://developer.hashicorp.com/vagrant/install

> Both are available on Windows, macOS, and Linux. After installing, restart your terminal so the `vagrant` and `VBoxManage` commands are on `PATH`.

## What's installed

| Tool             | Notes                                                            |
|------------------|------------------------------------------------------------------|
| **XFCE 4**       | Lightweight desktop with LightDM autologin (no goodies bloat)    |
| **Google Chrome** | Pre-installed (official Google repo)                            |
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
| **fzf**          | Fuzzy finder for the terminal                                    |
| **bat**          | `cat` with syntax highlighting (alias `bat` → `batcat`)          |
| **fd-find**      | Fast file finder (alias `fd` → `fdfind`)                         |
| **htop / btop**  | Process monitors                                                 |
| **tree**         | Directory tree visualization                                     |
| **direnv**       | Per-project environment variables                                |
| **Lazygit**      | Terminal Git UI (TUI) — staging, commits, branches               |
| **superfile**    | TUI file manager (`spf`) with Nerd Font icons                    |

## VM resources (dynamic allocation)

The Vagrantfile auto-detects host RAM and CPUs and allocates proportionally:

| Resource | Rule                          | Min    | Max    |
|----------|-------------------------------|--------|--------|
| RAM      | host − 6 GB reserved          | 2 GB   | 16 GB  |
| CPUs     | host − 2 reserved             | 1      | 8      |
| VRAM     | Fixed                         | 256 MB | 256 MB |
| Desktop  | XFCE 4 (via LightDM autologin) | —     | —      |

The reservation rule keeps ~6 GB of RAM and 2 CPUs free on the host for the OS and other apps (e.g. Chrome on the host), avoiding freezes when the VM is under heavy load.

Examples in practice:

| Host             | VM gets             |
|------------------|---------------------|
| 8 GB / 4 cores   | 2 GB RAM / 2 CPUs   |
| 16 GB / 8 cores  | 6.5 GB RAM / 4 CPUs |
| 32 GB / 12 cores | 16 GB RAM / 8 CPUs  |
| 64 GB / 16 cores | 16 GB RAM / 8 CPUs  |

The 16 GB / 8-core tier is a special case — allocating 10 GB to the VM left the host suffocated (Chrome, Claude Code, and other apps competing for ~6 GB). The carve-out reserves more RAM/CPU for the host.

Works on Windows, macOS, and Linux. You can override the values by editing `vm_memory` and `vm_cpus` near the top of the `Vagrantfile`.

## Extras configured automatically

- **XFCE desktop** with autologin — `vagrant up` opens directly to the desktop, no password prompt.
- **Ubuntu-like layout** — top bar (whiskermenu, centered clock, systray) + centered bottom dock with Docklike (pinned app icons that also show open windows, like Ubuntu's dock).
- **Pinned dock apps** — Chrome, Thunar, Tilix, Mousepad ready with one click. Open apps merge into their dock icon.
- **Arc-Dark theme** + **Papirus-Dark icons** + **Noto Sans font** + **DMZ-White cursor** — a clean modern dark look. Compositor enabled under VMSVGA.
- **Bidirectional clipboard and drag-and-drop** between host and VM (supervised systemd user units; survives X-event storms).
- **Google Chrome** pre-installed for in-VM browsing, with hardware-acceleration disabled via managed policy (avoids Chrome's deadlock under VMSVGA).
- **ED25519 SSH key** generated at `~/.ssh/id_ed25519` — public key is printed at the end of provisioning so you can paste it into GitHub/GitLab.
- **`~/projects`** — directory for your projects, pre-created.
- **Aliases** — `pf` (~/projects), `fd` (fdfind), `bat` (batcat).
- **Docker without sudo** — the `vagrant` user is in the `docker` group.
- **direnv** — hook installed in `.bashrc` so `.envrc` files load automatically.
- **Tilix** with 4% transparency as the default dock terminal.
- **Mousepad** with the Solarized Dark scheme and line numbers enabled.
- **Audio enabled** — output via Intel HD Audio (no microphone).
- **`vagrant` user password**: `docks`.
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

On the first run, Vagrant downloads the Debian 13 image, creates the VirtualBox VM, and runs all of provisioning (package install + XFCE setup). This takes a few minutes depending on your connection. The VM auto-reboots after provisioning and lands you in the XFCE desktop with autologin as `vagrant`.

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
├── scripts/            # numbered shell scripts, fetched from GitHub at provision time
│   ├── _lib.sh         # shared helpers (fetch_asset)
│   ├── 10-apt-repos.sh
│   ├── 20-packages.sh
│   ├── 30-guest-additions.sh
│   ├── 40-xfce-base.sh
│   ├── 41-xfce-theme.sh
│   ├── 50-vboxclient-supervisor.sh
│   ├── 51-vbox-autoresize.sh
│   ├── 60-apps-tilix-mousepad.sh
│   ├── 65-superfile-fonts.sh
│   ├── 70-nodejs-claude.sh
│   ├── 80-git-ssh-lazygit.sh
│   ├── 85-secrets-env.sh
│   ├── 90-claude-config-sync.sh
│   ├── 95-permissions.sh
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
