# 0008 — VS Code editor (replaces Mousepad)

**Status:** Proposed (trial — stacked on the Night Owl desktop branch)
**Branch:** `feat/night-owl-desktop`
**Scope:** install Visual Studio Code, deploy the user's `settings.json` +
extensions at provision time, pin it on the dock, and **remove Mousepad**. New
`scripts/66-vscode.sh` + `assets/vscode/*`. Supersedes the Mousepad portion of
`plans/0007-night-owl-desktop.md` (decision #2 there).

## Problem

Mousepad is a bare GTK text editor — no real search across files, no language
intelligence. The user works in VS Code (Night Owl, syntax highlighting) and
wants the box to match: VS Code installed, **their** settings applied
automatically when the VM provisions, VS Code on the taskbar, and Mousepad gone.

## Root cause (why config is needed at all)

A bare `apt install code` gives an unconfigured editor: default Dark+ theme (not
Night Owl — that is the `sdras.night-owl` *extension*, which is not installed by
default), default settings, and Mousepad still installed + pinned. VS Code is
also not in Debian's repos — it needs Microsoft's apt repo.

## Decision

1. **Install `code` from Microsoft's apt repo.** Key + source added in
   `10-apt-repos.sh` (same `signed-by` keyring pattern as Chrome/Docker/gh),
   package added to `20-packages.sh` — exactly the Chrome precedent (repo in 10,
   package in 20, config later).
2. **Settings live in this repo.** `assets/vscode/settings.json` →
   `~/.config/Code/User/settings.json`, **first-provision-only** (guarded by
   `/var/lib/vagrant-provisioned`) so GUI changes are preserved on re-provision.
   Shipped with a sensible Night Owl default; the user replaces it with their
   host file (`~/.config/Code/User/settings.json` on Linux, the
   `Application Support` / `%APPDATA%` paths elsewhere) and re-provisions.
3. **Extensions from a repo-managed list.** `assets/vscode/extensions.txt` (one
   ID per line, `#`-comments ignored) is looped through `code --install-extension`
   as vagrant, every provision (idempotent — already-installed extensions are
   skipped; `FORCE_REINSTALL=1` adds `--force`). Seeded with `sdras.night-owl` so
   the `"workbench.colorTheme": "Night Owl"` in settings actually renders; the
   user appends their own (`code --list-extensions` on the host). One bad ID
   tolerates failure so it can't abort provisioning.
4. **Remove Mousepad.** Drop the `mousepad` apt package, rename
   `60-apps-tilix-mousepad.sh` → `60-tilix.sh` (Tilix-only), delete the Night Owl
   GtkSourceView scheme added for it in 0007 (`assets/gtksourceview/night-owl.xml`
   + its deploy), swap the docklike pin and the `text/plain` default handler from
   `org.xfce.mousepad.desktop` to `code.desktop`.

## Alternatives considered

### settings.json source

| Option | Verdict |
| --- | --- |
| **In this repo (`assets/vscode/`)** | **Chosen.** Self-contained + version-controlled here; "fetch" = copy the host file in once. Seeded first-provision-only. |
| Pull from `DocksDocks/public` (the SSOT `90-claude-config-sync.sh` clones) | Viable and consistent with the agent-config sync, but spreads VS Code config into a second repo the user must maintain. |
| VS Code cloud Settings Sync | Live + always-current, but interactive (a GitHub sign-in per box) — not automatic at provision, which was the request. |

### Extensions

| Option | Verdict |
| --- | --- |
| **Night Owl + repo-managed list** | **Chosen.** `extensions.txt` is version-controlled and mirrors the host via `code --list-extensions`. |
| Just the Night Owl theme | Minimal; underdelivers — the user has a real extension set. |
| Settings only, none | Rejected — the Night Owl theme wouldn't even render. |

### Mousepad

| Option | Verdict |
| --- | --- |
| **Uninstall entirely** | **Chosen** (user's call). VS Code is the only editor; the 0007 Mousepad scheme is dropped as dead. |
| Keep installed, just unpin | Lower-risk fallback; rejected — the user wanted it gone. |

## How it's enabled at provision time

- `10-apt-repos.sh` — adds the Microsoft `packages.microsoft.com/repos/code` apt
  source + key.
- `20-packages.sh` — installs `code`; no longer installs `mousepad`.
- `66-vscode.sh` — installs the extension list (every provision) and seeds
  `settings.json` (first provision only). Skips gracefully if `code` is absent.
- `40-xfce-base.sh` + `assets/docklike.rc` — VS Code pinned where Mousepad was.
- `assets/mimeapps.list` — `text/plain` opens in VS Code.

## Verification steps

- `shellcheck -x scripts/{10,20,60,66}-*.sh` → clean (only the expected SC1091
  `_lib.sh` info); `bash -n` OK.
- `settings.json` body (comments stripped) parses as valid JSON — 14 keys,
  `workbench.colorTheme = Night Owl`.
- `extensions.txt` non-comment lines = `sdras.night-owl`.
- `grep -rni mousepad scripts/ assets/ Vagrantfile` → empty (fully removed).
- `SCRIPTS` array: `60-tilix`, `65-superfile-fonts`, `66-vscode` in order.
- Post-`vagrant up` (visual): VS Code pinned on the dock and launches; opening a
  file shows Night Owl (extension installed); double-clicking a `.txt` in Thunar
  opens VS Code; Mousepad absent from the menu.

## Caveat

Extension installs need the VS Code Marketplace reachable at provision time
(failures are logged per-extension, not fatal). `settings.json` is seeded once —
edits made in the GUI survive re-provision, so to push a new baseline from the
repo you either edit in-VM or `vagrant destroy && up`. The shipped settings are a
placeholder until the user pastes their own.

## Files changed

- `scripts/66-vscode.sh` (new)
- `assets/vscode/settings.json` (new), `assets/vscode/extensions.txt` (new)
- `scripts/10-apt-repos.sh` — Microsoft apt repo
- `scripts/20-packages.sh` — `+code`, `-mousepad`
- `scripts/60-apps-tilix-mousepad.sh` → `scripts/60-tilix.sh` (rename; Mousepad stripped)
- `assets/gtksourceview/night-owl.xml` (deleted — was the 0007 Mousepad scheme)
- `assets/docklike.rc`, `assets/mimeapps.list`, `scripts/40-xfce-base.sh` — dock + default handler
- `Vagrantfile` — `SCRIPTS` (`60-tilix`, `+66-vscode`)
- `plans/0007-night-owl-desktop.md` — Mousepad decision marked superseded
- `AGENTS.md`, `.agents/skills/xfce-desktop-config/SKILL.md`
