# 0002 — Split the Vagrantfile, fetch scripts from GitHub at provision time

**Status:** Proposed (not yet implemented)
**Branch:** `refactor/split-vagrantfile` (future — separate from the clipboard fix)
**Scope:** `Vagrantfile`, new `scripts/`, new `assets/`

## Problem

`Vagrantfile` is ~515 lines, most of it a single inline shell heredoc. Pain points:

- Hard to scan. Every concern (apt repos, packages, GA, XFCE theme, Tilix, Node, SSH, …) is interleaved in one huge string.
- XML and dconf blobs aren't real files, so they can't be linted, syntax-checked, or reviewed as their own units.
- The shell body can't be `shellcheck`ed.
- Re-running a single concern means re-running the whole provisioner.
- Diffs are noisy: every touch looks like a change to one giant file.

## Goal

Ship a **single-file Vagrantfile** end users can `curl` or download and run — while keeping per-step scripts editable and reviewable in isolation. Achieve that by fetching scripts from this public repo at provision time, with three safeguards: ref pinning, a local-dev override, and retries on transient network failures.

## Decision

Split the current inline heredoc into per-concern shell scripts under `scripts/` and lift the XML/dconf/systemd blobs into `assets/`. Keep everything in this same repo (`docksdocks/vagrant`) — no second repo, no submodule. The Vagrantfile fetches the scripts from `https://raw.githubusercontent.com/docksdocks/vagrant/<ref>/scripts/<name>.sh` at provision time.

### Target repo layout

```
docksdocks/vagrant/                      (public)
├── Vagrantfile                          (~80 lines; the one file users download)
├── README.md
├── plans/
│   ├── 0001-clipboard-supervisor.md
│   └── 0002-split-vagrantfile.md        (this document)
├── scripts/
│   ├── 10-apt-repos.sh         40-xfce-base.sh           60-apps-tilix-mousepad.sh
│   ├── 20-packages.sh          41-xfce-theme.sh          70-nodejs-claude.sh
│   ├── 30-guest-additions.sh   50-vboxclient-supervisor.sh   80-git-ssh-lazygit.sh
│   │                           51-vbox-autoresize.sh     90-claude-config-sync.sh
└── assets/
    ├── xfwm4.xml  xfce4-panel.xml  tilix.dconf  gtk.css
    └── systemd/vbox-clipboard.service  systemd/vbox-draganddrop.service
```

Numbered prefixes with gaps (`10`, `20`, `30`, …) are cosmetic — Vagrant executes provisioners in the order they're declared in the Vagrantfile regardless of filename — but they make `ls scripts/` sort in execution order and leave room to insert new steps (`25-foo.sh`) without renaming the rest. Standard sysv-style convention.

### End-user flow

```
curl -fsSL https://raw.githubusercontent.com/docksdocks/vagrant/main/Vagrantfile > Vagrantfile
vagrant up
```

One file downloaded. The Vagrantfile fetches its own scripts and assets from the same repo at the pinned ref.

### Vagrantfile structure

```ruby
SCRIPTS_REPO = "docksdocks/vagrant"                       # same repo, public
SCRIPTS_REF  = ENV.fetch("VAGRANT_SCRIPTS_REF", "main")   # pin to a tag in releases
LOCAL_DIR    = ENV["VAGRANT_SCRIPTS_DIR"]                 # dev-mode override

SCRIPTS = %w[
  10-apt-repos 20-packages 30-guest-additions
  40-xfce-base 41-xfce-theme
  50-vboxclient-supervisor 51-vbox-autoresize
  60-apps-tilix-mousepad
  70-nodejs-claude 80-git-ssh-lazygit
  90-claude-config-sync
]

Vagrant.configure("2") do |config|
  # ... host-detect + vb.customize block kept inline (it's Ruby, not shell) ...

  SCRIPTS.each do |name|
    env = { "SCRIPTS_REF" => SCRIPTS_REF, "SCRIPTS_REPO" => SCRIPTS_REPO }
    if LOCAL_DIR
      config.vm.provision name, type: "shell",
                                path: "#{LOCAL_DIR}/#{name}.sh", env: env
    else
      url = "https://raw.githubusercontent.com/#{SCRIPTS_REPO}/#{SCRIPTS_REF}/scripts/#{name}.sh"
      config.vm.provision name, type: "shell", env: env, inline: <<~SH
        set -euo pipefail
        curl -fsSL --retry 4 --retry-delay 2 "#{url}" -o /tmp/#{name}.sh
        bash /tmp/#{name}.sh
      SH
    end
  end
end
```

### Safeguards

- **Ref pinning for reproducibility.** `SCRIPTS_REF` defaults to `main` but the committed Vagrantfile pins a tag once v1.0.0 is cut. `git checkout <old Vagrantfile sha>` then reproduces that VM forever.
- **Local-dev override.** `VAGRANT_SCRIPTS_DIR=./scripts vagrant provision` uses local files instead of fetching — no push-to-test loop while iterating on a script.
- **Asset fetching inside scripts.** Each script does `curl -fsSL https://raw.githubusercontent.com/$SCRIPTS_REPO/$SCRIPTS_REF/assets/foo.xml -o /tmp/foo.xml`. In local-dev mode the scripts detect `$VAGRANT_SCRIPTS_DIR` and read assets from `$VAGRANT_SCRIPTS_DIR/../assets/` instead. Scripts are versioned atomically with their assets via the shared ref.
- **TLS + retries.** `raw.githubusercontent.com` is TLS-terminated by GitHub; `curl --retry 4 --retry-delay 2` rides out transient failures.
- **Fail loudly.** `curl -f` on every fetch so HTTP 404s abort instead of piping empty strings into `bash`.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Keep everything inline | Status quo. Solves nothing. |
| Local scripts only (no fetch) | Works, but end users would have to `git clone` the whole repo instead of downloading one `Vagrantfile`. Loses the one-file-UX goal. |
| Separate `vagrant-scripts` repo | Splits versioning across two repos, bumping SCRIPTS_REF becomes a cross-repo dance. Same repo is simpler with no real downside for a personal dev-box. |
| Git submodule for scripts | Submodules are annoying and the main repo still contains a pinned ref. Same reproducibility as ref-pinning, more friction. |

## Known tradeoffs (accepted)

- Re-provision requires network. Acceptable — `vagrant up` already depends on `deb.debian.org`, `download.virtualbox.org`, `nodesource`, `docker.com`, etc. GitHub is one more upstream, not a category change.
- Account compromise on `docksdocks/vagrant` = root compromise on the guest. Same risk profile as any `curl | bash` dev-box installer; acceptable for a personal dev box where the user owns the repo.
- Repo **must be public** for unauthenticated `curl` from `raw.githubusercontent.com` to work. (Private repos would need a PAT in the URL — defeats the one-file UX.)

## Pre-flight: repo is safe to make public

Audit run before proposing this:

- Only tracked files today: `CLAUDE.md`, `README.md`, `Vagrantfile` (3 files, 60 commits).
- No deleted files in history (`git log --all --diff-filter=D` empty) → nothing to recover from past revisions.
- No private keys, tokens, API keys, PATs, AWS creds, or real emails anywhere in current files or history.
- Only "credential" present is the intentional `vagrant:docks` VM password (`Vagrantfile`, `CLAUDE.md`, commit `54871bb`) — accepted.
- The SSH keypair the VM uses is **generated inside the guest at provision time**, never stored in the repo.

No history rewrite or secret cleanup is required before flipping visibility.

## Rollout

1. Make `docksdocks/vagrant` public on GitHub.
2. On `refactor/split-vagrantfile`, do the split **without behavioural change**. One commit per concern, moving a section of the inline heredoc into its own `scripts/NN-*.sh` with any XML/dconf/systemd blobs lifted into `assets/`. Test each step via `VAGRANT_SCRIPTS_DIR=./scripts vagrant provision`.
3. Also in this branch, collapse the Vagrantfile to the ~80-line orchestrator described above.
4. Once green end-to-end, merge to `main` and tag `v1.0.0`.
5. Update `SCRIPTS_REF = "v1.0.0"` in the Vagrantfile (pin to the tag, not `main`). Commit that pin.
6. Validate: `vagrant destroy -f && vagrant up` from a fresh directory containing **only** the downloaded Vagrantfile, with no env vars set — confirms the end-user fetch-from-GitHub path.

## Verification

- `vagrant destroy -f && vagrant up` (no env vars) succeeds and produces a VM functionally identical to pre-refactor (installed packages, XFCE config, LightDM autologin, clipboard working, auto-resize working, all CLI tools present).
- Same run with `VAGRANT_SCRIPTS_DIR=./scripts` produces the same VM from local files.
- Checking out an older Vagrantfile commit (with an older `SCRIPTS_REF`) still reproduces the older VM — proves ref pinning actually buys reproducibility.
- `shellcheck scripts/*.sh` passes clean (a win impossible with the inline heredoc).
- `vagrant provision --provision-with 50-vboxclient-supervisor` re-runs just that step — proves incremental provisioning works.
