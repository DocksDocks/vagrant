---
name: plans-adr-format
description: Use when authoring or reviewing a design decision record under plans/ — the NNNN-kebab-case.md naming (0001-clipboard-supervisor.md, 0002-split-vagrantfile.md as the two reference exemplars), the required section structure (Status Accepted/Proposed/Superseded — Branch — Scope — Problem — Root cause — Decision — Alternatives considered as a markdown table — How it's enabled at provision time — Verification steps — Files changed), citing upstream Oracle / NixOS / community-forum bug references inline (VBox #5266, VBox #19234, NixOS/nixpkgs#65542, VirtualBox/virtualbox#568, VBox #15417), and pre-flight repo-safety checklists when a decision flips repo visibility (no PATs, AWS keys, real emails, only the intentional vagrant:docks credential). Not for skill authoring, README/CLAUDE.md edits, or per-script implementation comments.
user-invocable: false
metadata:
  pattern: tool-wrapper
  source_files:
    - "plans/0001-clipboard-supervisor.md"
    - "plans/0002-split-vagrantfile.md"
  updated: "2026-05-03"
---

# Plans ADR Format

<constraint>
Every plan file MUST have all nine required sections. Status, Branch, Scope, Problem, Root cause, Decision, Alternatives considered (as a table), How it's enabled at provision time, Verification steps, Files changed. Omitting "How it's enabled at provision time" is the most common miss — implementation detail belongs in the plan, not just in the script.
</constraint>

<constraint>
The "Alternatives considered" section MUST be a markdown table with columns `| Option | Why rejected |`. Prose alternatives lists are harder to scan and miss the rejection rationale.
</constraint>

## When to Use

- Recording a non-obvious architecture decision (workaround for an upstream bug, script-ordering dependency, security constraint).
- Documenting why a particular approach was chosen over alternatives.
- Reviewing an existing plan for completeness.
- Pre-flighting a change that affects repo visibility or public security posture.
- Citing upstream bug tracker references for a known issue.

## File Naming

```
plans/NNNN-kebab-case.md
```

Examples: `plans/0001-clipboard-supervisor.md`, `plans/0002-split-vagrantfile.md`.

NNNN is zero-padded to 4 digits. Next free slot after 0002 is 0003.

## Required Section Structure

| Section | Purpose | Notes |
|---|---|---|
| `# NNNN — Title` | H1 with plan number + title | Must match filename |
| `**Status:** Accepted/Proposed/Superseded` | Lifecycle state | Proposed = under review, not yet merged |
| `**Branch:**` | Git branch where implemented | Or "main" if merged |
| `**Scope:**` | What files/systems are affected | E.g. "`Vagrantfile` only" |
| `## Problem` | What breaks without this plan | Observable failure, not the fix |
| `## Root cause` | The underlying technical reason | Cite bug tracker refs here |
| `## Decision` | What was decided and why | Concrete, positive framing |
| `## Alternatives considered` | Table of rejected options | `\| Option \| Why rejected \|` |
| `## How it's enabled at provision time` | Implementation detail | Which script, which lines |
| `## Verification` | How to confirm the fix works | Numbered steps, testable |
| `## Files changed` | Diff summary | Which files, what changed |

Source: `plans/0001-clipboard-supervisor.md` (full document), `plans/0002-split-vagrantfile.md` (full document).

## Upstream Bug Reference Style

Cite in "Root cause" section inline with link text:

```markdown
This is an upstream Oracle bug with a 15-year tail:
- VBox ticket [#5266 "Shared Clipboard stops working"](https://www.virtualbox.org/ticket/5266) — never fully fixed.
- NixOS [nixpkgs#65542 "VBoxClient --clipboard terminates silently"](https://github.com/NixOS/nixpkgs/issues/65542).
```

Source: `plans/0001-clipboard-supervisor.md:22-27`.

Known bug references in this repo:
- Oracle VBox [#5266](https://www.virtualbox.org/ticket/5266) / [#6150](https://www.virtualbox.org/ticket/6150) / [#19234](https://www.virtualbox.org/ticket/19234) — clipboard silent termination
- VirtualBox/virtualbox [#568](https://github.com/VirtualBox/virtualbox/issues/568) — VMSVGA auto-resize silent failure
- Oracle VBox [#15417](https://www.virtualbox.org/ticket/15417) — Chrome GPU deadlock under VMSVGA
- NixOS [nixpkgs#65542](https://github.com/NixOS/nixpkgs/issues/65542) — VBoxClient --clipboard terminates silently
- Debian bug [#1110834](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1110834) — debian/trixie64 libvirt-only

## Pre-Flight Checklist (Public Repo Safety)

Required before any plan that could expose secrets:

```
- [ ] No private keys, tokens, API keys, PATs in tracked files or git history
- [ ] No real email addresses (other than intentional public ones)
- [ ] Only intentional credential: vagrant:docks VM password
- [ ] SSH keypair generated inside guest at provision time (never in repo)
- [ ] git log --all --diff-filter=D (no deleted files containing secrets)
```

Source: `plans/0002-split-vagrantfile.md:114-124`.

## Status Values

| Status | Meaning |
|---|---|
| `Proposed` | Decision proposed, not yet merged |
| `Accepted` | Merged and active |
| `Superseded` | Replaced by a later plan (add "Superseded by NNNN") |

## Alternatives Table Example

```markdown
| Option | Why rejected |
|---|---|
| Shell `while` supervisor in autostart | No journaled logs, harder to parallelize, non-standard |
| Cron/watch-style poll | Polling is wasteful; doesn't restart immediately on death |
| Wait for Oracle to fix upstream | Bug filed 2009, still open |
```

Source: `plans/0001-clipboard-supervisor.md:52-59`.

## Gotchas

**Status "Proposed" on a merged plan**: update to "Accepted" when the branch merges. `plans/0002-split-vagrantfile.md` is still "Proposed" because the split was implemented but the plan predated the merge. Keep Status accurate.

**Missing "How it's enabled at provision time"**: this is the section most often skipped. It's load-bearing — future maintainers need to know which script and which lines implement the decision, not just that it was decided.

**Alternatives table with prose instead of table**: markdown tables enforce the `| Option | Why rejected |` structure and are easier to scan in diffs. Prose alternatives drift into argumentative justification rather than concise rejection rationale.

**No verification steps**: a plan without testable verification steps cannot confirm the decision was correctly implemented. Always include at least one shell command that proves the fix works (e.g., `systemctl --user status`, `chrome://policy`, `vagrant provision --provision-with NN-name`).
