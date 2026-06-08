# 0011 — Run scripts from the clone by default (local-first, remote fallback)

**Status:** Accepted
**Branch:** `claude/vibrant-heisenberg-LuQZM`
**Scope:** `Vagrantfile` (`LOCAL_DIR` selection + the inline per-script runner), `AGENTS.md`, `.agents/skills/vagrantfile-orchestrator/SKILL.md`

## Problem

The intended end-user flow is "clone the repo, run `vagrant up`, pick a profile". But provisioning fetched every script from `raw.githubusercontent.com/docksdocks/vagrant/main/scripts/<name>.sh` unless `VAGRANT_SCRIPTS_DIR` was set by hand. Two concrete failures:

- **A clone on a feature branch runs `main`, not the branch.** `SCRIPTS_REF` defaults to `main`, so edits committed to a branch (or even uncommitted local edits) are silently ignored on `vagrant up` / `vagrant provision`. You think you're testing your change; you're running `main`. This is exactly what blocks validating a fix branch.
- **Provisioning needs the network even though all the code is already on disk** (cloned, and mounted at `/vagrant`). A GitHub blip aborts a `curl -f`.

## Root cause

Per [plans/0002-split-vagrantfile.md](0002-split-vagrantfile.md) the Vagrantfile was designed around a "download just the Vagrantfile and go" UX, so REMOTE fetch was the *default* and LOCAL was opt-in via `VAGRANT_SCRIPTS_DIR`. For the far more common "git clone" case that default is backwards: the synced folder already exposes the exact cloned tree at `/vagrant` (VirtualBox vboxsf, or UTM virtFS), so the right files are sitting there unused.

## Decision

Make the script source **auto-detect**, defaulting to LOCAL when this is a clone, with a per-script REMOTE fallback so LOCAL is always safe to prefer.

Selection (host-side Ruby):

```ruby
_repo_scripts = File.join(File.dirname(File.expand_path(__FILE__)), "scripts")
LOCAL_DIR = ENV.key?("VAGRANT_SCRIPTS_DIR") ? ENV["VAGRANT_SCRIPTS_DIR"] :
            (File.file?(File.join(_repo_scripts, "_lib.sh")) ? "./scripts" : nil)
```

- `VAGRANT_SCRIPTS_DIR` set → honoured verbatim. Setting it to empty (`VAGRANT_SCRIPTS_DIR=`) forces REMOTE even from a clone (handy to test what `main` would do).
- Otherwise: if `scripts/_lib.sh` sits next to the Vagrantfile (a clone) → LOCAL; else (bare Vagrantfile downloaded alone) → REMOTE.

Per-script runner — prefer the on-disk copy, fall back to fetch if the share didn't mount:

```sh
if [ -n "${VAGRANT_SCRIPTS_DIR:-}" ] && [ -f /vagrant/scripts/#{name}.sh ]; then
  export VAGRANT_LIB_PATH=/vagrant/scripts/_lib.sh
  bash /vagrant/scripts/#{name}.sh
else
  # bootstrap curl if missing, cache _lib.sh at /tmp, curl this script, run it
fi
```

`fetch_asset` (in `_lib.sh`) already mirrors this: it copies `/vagrant/assets/<rel>` when present and curls otherwise, so a partially-mounted share still resolves every asset. The net effect: a clone runs exactly the cloned code offline; a bare Vagrantfile still works from GitHub; and a broken share degrades to REMOTE per file instead of failing.

### Line-ending safeguard (required for Windows)

Running the on-disk copy makes the working tree's line endings load-bearing. Git for Windows defaults to `core.autocrlf=true`, so a clone there would convert `*.sh` (and the assets) to CRLF — and `bash /vagrant/scripts/NN.sh` then dies on the `\r` (`set: pipefail: invalid option name`), while a CRLF `_lib.sh` fails to source at all. The REMOTE path never had this problem because `raw.githubusercontent.com` always serves LF. A committed **`.gitattributes`** (`* text=auto eol=lf` plus explicit `*.sh`/`Vagrantfile`/asset rules) forces LF in the working tree on every host, neutralising the issue at the source (both scripts AND assets). A box cloned before `.gitattributes` existed can be repaired with `git add --renormalize . && git checkout -- .`, a re-clone, or `VAGRANT_SCRIPTS_DIR= vagrant provision` (force REMOTE).

## Alternatives considered

| Option | Why rejected |
|---|---|
| Keep REMOTE default | The status quo; a cloned branch silently runs `main`, and provisioning needs the network for code already on disk. |
| Default `SCRIPTS_REF` to the current git branch | Still REMOTE: needs the branch pushed, still hits the network, and reads `.git/HEAD` host-side which is brittle (detached HEAD, worktrees). LOCAL needs none of that. |
| Always LOCAL (drop REMOTE) | Breaks the documented "download only the Vagrantfile" path from plans/0002. |
| LOCAL only on VirtualBox, REMOTE on UTM | Avoids trusting virtFS, but splits behaviour by platform; the per-script fallback makes a blanket LOCAL default safe on both. |

## How it's enabled at provision time

`LOCAL_DIR` is computed once when Vagrant evaluates the Vagrantfile and forwarded to every provisioner as `VAGRANT_SCRIPTS_DIR` (via the `env` hash, `.compact`-ed). The inline runner (one shell provisioner per `SCRIPTS` entry) branches on `VAGRANT_SCRIPTS_DIR` **and** the on-disk presence of `/vagrant/scripts/<name>.sh`, choosing LOCAL or the curl path accordingly and exporting the matching `VAGRANT_LIB_PATH`.

## Verification

1. Clone the branch, `vagrant up` with no env vars, watch the provision log: scripts run via `bash /vagrant/scripts/NN-*.sh` (no `raw.githubusercontent.com` fetch lines).
2. Edit a local script (e.g. add an `echo` to `scripts/99-finalize.sh`), `vagrant provision`, confirm the new output appears — proves local edits take effect without pushing.
3. Force remote from the clone: `VAGRANT_SCRIPTS_DIR= vagrant provision` → log shows the `curl … -o /tmp/NN-*.sh` path.
4. `ruby -c Vagrantfile` → `Syntax OK`.

## Files changed

- `Vagrantfile` — `LOCAL_DIR` now auto-detects a clone (`ENV.key?` + `File.file?` on `scripts/_lib.sh`); the inline runner requires `/vagrant/scripts/<name>.sh` to exist before taking the LOCAL branch, else falls back to REMOTE; updated the surrounding comments.
- `.gitattributes` (new) — `* text=auto eol=lf` + explicit `*.sh`/`Vagrantfile`/asset rules, so Windows clones can't feed CRLF scripts to the guest now that LOCAL is the default.
- `AGENTS.md` — architecture paragraph + UTM provider note updated to "local-by-default, remote fallback"; added the CRLF "Common Issues" entry.
- `.agents/skills/vagrantfile-orchestrator/SKILL.md` — added the "Local-by-default script source" key decision; `metadata.updated` bumped.
