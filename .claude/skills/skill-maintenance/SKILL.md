---
name: skill-maintenance
description: Use when adding, refreshing, splitting, merging, or rewriting a project skill under .claude/skills/, validating a skill's frontmatter (name kebab-case matching directory, description starts with "Use when…" and contains "Not for…", user-invocable false, metadata.source_files, metadata.updated YYYY-MM-DD), checking the 500-line body cap and reference-file size budgets, bumping metadata.updated after a code change touches a skill's source_files, running guard-skills.sh / score-skills.sh validators, or vendoring a third-party skill (with the upstream source / license / vendored_at frontmatter block that relaxes kit-specific checks). Not for agent authoring (use agents directory), ADR plans/, or shell-script bodies under scripts/.
user-invocable: false
metadata:
  pattern: reviewer
  source_files:
    - ".claude/skills/provisioning-script-conventions/SKILL.md"
    - ".claude/skills/vagrantfile-orchestrator/SKILL.md"
    - ".claude/skills/virtualbox-vmsvga-gotchas/SKILL.md"
    - ".claude/skills/xfce-desktop-config/SKILL.md"
    - ".claude/skills/secrets-env-convention/SKILL.md"
    - ".claude/skills/plans-adr-format/SKILL.md"
    - ".claude/skills/skill-maintenance/SKILL.md"
  updated: "2026-05-03"
---

# Skill Maintenance

<constraint>
Every SKILL.md body MUST be ≤500 lines (excluding frontmatter). Every `references/` file MUST be 30-150 lines. Exceeding these budgets causes the skill to load more tokens than the description-only discovery phase saved.
</constraint>

<constraint>
Descriptions MUST start with "Use when…" (CSO-compliant) and contain at least one "Not for…" exclusion clause. Claude Code's discovery phase loads only `name` + `description`; a bad description causes the wrong skill to trigger (or the right skill to never trigger).
</constraint>

<constraint>
After ANY code change that touches a file listed in `metadata.source_files`, bump `metadata.updated` to today's date in that skill. Stale `updated` dates are the primary signal that a skill may be out of sync.
</constraint>

## When to Use

- A script in `scripts/` changes its preamble, env-var contract, or idempotency pattern.
- A new asset is added to `assets/` and a skill documents asset deployment.
- A VirtualBox setting changes in the Vagrantfile.
- A new provisioning script is added (update `provisioning-script-conventions` source_files + SCRIPTS table).
- A plan file is added under `plans/`.
- Reviewing a skill for frontmatter correctness or body size.
- Vendoring a skill from an external source.
- Deciding whether to put knowledge in the SKILL.md body vs a `references/` file.

## Frontmatter Schema

```yaml
---
name: kebab-case-matching-directory       # required; must match dirname
description: "Use when <trigger>... Not for <exclusion>..."  # required; ≤1024 chars; CSO
user-invocable: false                     # required; always false for tool-wrapper skills
metadata:
  pattern: tool-wrapper                   # or: reviewer (for meta skills)
  source_files:                           # required; list of files that inform this skill
    - "scripts/NN-name.sh"
    - "assets/filename.xml"
  updated: "YYYY-MM-DD"                  # required; bump on every relevant code change
---
```

For vendored (third-party) skills, add an `upstream:` block:

```yaml
upstream:
  source: "https://github.com/org/repo/path/to/SKILL.md"
  license: "MIT"
  vendored_at: "2026-05-03"
```

The `upstream:` block signals `guard-skills.sh`/`score-skills.sh` to relax kit-specific checks (CSO start-prefix, `user-invocable`, `metadata.updated`). Universal structural checks still apply (fenced frontmatter, name matches directory, description length, 500-line cap).

## File Layout

```
.claude/skills/<name>/
  SKILL.md              # frontmatter + body (≤500 lines body)
  references/           # optional; detail files (30-150 lines each)
    <topic>.md
    <topic2>.md
```

Directory name = skill `name` frontmatter field (kebab-case).

## Body Structure (U-shaped Attention)

1. `# <Skill Title>` — one line
2. `<constraint>` blocks — critical non-negotiable rules (top, high attention)
3. `## When to Use` — bullet trigger scenarios
4. `## Core Patterns` — tables, code blocks, file:line references
5. `## Key Decisions` — 2-5 bullets with file:line refs
6. `## Gotchas` — concrete failure scenarios (bottom, high attention)
7. `## References` — list of `references/` files with when-to-read conditions

## Body vs References Decision

| Put in body | Put in references/ |
|---|---|
| Triggers, gotchas, core pattern signatures | Full implementation listing |
| 2-5 line code snippets | Extended code blocks (10+ lines) |
| Quick-reference tables | Detailed comparison tables |
| Common-path patterns | Edge-case handling |
| The "what" and "when" | The "why in depth" and "how exactly" |

References are loaded on demand when the skill's body says "Read references/topic.md when: ...". Keep body ≤500 lines; each reference 30-150 lines.

## Bump Workflow

When a source file changes:

1. Identify which skills list the changed file in `metadata.source_files`.
2. Re-read the changed file at the affected lines.
3. Update the skill body if the pattern changed.
4. Bump `metadata.updated: "YYYY-MM-DD"` to today.
5. If a references/ file covered the changed pattern, update that too.

## Adding a New Skill

1. Create `.claude/skills/<name>/SKILL.md` with valid frontmatter.
2. Write body ≤500 lines; extract detail to `references/` as needed.
3. Verify `name` frontmatter matches directory name exactly.
4. Verify description starts "Use when…" and contains "Not for…".
5. Verify `metadata.source_files` lists actual project files (not invented paths).
6. Run `bash guard-skills.sh` (if it exists — see note below).
7. Run `bash score-skills.sh` (if it exists — see note below).

## Validators

**NOTE:** As of 2026-05-03 this project does not yet have `guard-skills.sh` or `score-skills.sh` in the repo root. These validators are standard kit tooling from the agentskills.io ecosystem. When they are added, run them after every skill create/update.

Expected behavior when present:
- `guard-skills.sh` — structural checks: fenced frontmatter, name matches directory, description ≤1024 chars, body ≤500 lines, `user-invocable` present. Exits non-zero on failure.
- `score-skills.sh` — quality scoring: CSO compliance, source_files reachable, updated date not stale, references within size budget. Returns a score (not a pass/fail).

## CSO Description Rules

| Rule | Good | Bad |
|---|---|---|
| Starts with "Use when…" | "Use when adding a script to scripts/..." | "This skill covers script conventions..." |
| Contains "Not for…" | "Not for XFCE config or Vagrantfile edits" | (no exclusion clause) |
| ≤1024 chars | Measured with `wc -c` | Overflow truncates in some tools |
| ≥5 project-specific identifiers | script names, file paths, env var names | Generic words only |
| Trigger conditions, not capabilities | "Use when fetch_asset fails..." | "Covers the fetch_asset function..." |

## When to Skip Updating a Skill

- Typo fix in a comment with no semantic change.
- Rename of a file that is not in any skill's `source_files`.
- Test-only changes (this project has no test suite, but applies to future additions).
- Changes to `plans/` that don't alter implementation patterns already documented.

Do NOT skip if: a function signature changes, a new env var is introduced, an idempotency guard pattern changes, or a new file is added to `assets/` that should be documented.

## Gotchas

**`name` frontmatter does not match directory**: Claude Code's discovery uses the directory name for lookup; a mismatch causes the skill to load under the wrong name or not at all. Always make them identical.

**description > 1024 chars**: some skill-loading implementations truncate the description at 1024 chars, causing the CSO trigger conditions at the end to be lost. Keep descriptions concise; move detail to the body.

**`source_files` pointing to non-existent paths**: staleness detector cannot verify the skill. Always use paths relative to the repo root that actually exist. Remove stale paths from the array when files are deleted.

**Skill body at exactly 500 lines**: the constraint is ≤500 body lines (excluding frontmatter). Count from the first `#` heading to the last line. Use `wc -l` on the body only (strip frontmatter first) to verify.

**References file < 30 lines**: too short to justify a separate file; move the content into the body. References < 30 lines add file-open overhead without detail payoff.
