---
description: Reconcile the project's CLAUDE.md against the canonical devkit-compliant structure. Reads CLAUDE.md, detects missing or semantically-overlapping sections, and proposes section-by-section merges with the documenter skill's "propose before writing" discipline. Idempotent — running on an already-compliant CLAUDE.md reports "nothing to merge." Not gated on an active feature; usable anytime.
---

Drive an interactive merge between the project's existing `CLAUDE.md` and the canonical structure a devkit-compliant `CLAUDE.md` should have. One `/claude-md-merge` invocation walks the user through every chunk that needs adding or reconciling and leaves the file with a clean structure that supports `/feature-start`'s orient phase, the documenter skill's *what lives where* map, and the doc-drift hook's expectations.

`/claude-md-merge` is **housekeeping**, not feature work. It is not gated on an active feature — run it before adopting the pack, after declining `install.sh`'s append prompt, or after a pack update changed the canonical template.

## Arguments

None. Operates on `CLAUDE.md` in the current working directory (the project root).

## Preconditions

1. `CLAUDE.md` exists in the project root. If absent, stop and recommend `./install.sh` instead — fresh-stamp from template is cleaner than reconstructing from scratch.
2. `.claude/devkit-orientation.md` exists. If absent, stop and recommend running `install.sh` first — the orientation reference points at that file, so writing the reference before the file exists creates a dangling pointer.

If either fails, surface it with the recommended remediation and exit. Load the `documenter` skill and proceed when both pass.

## Run

The loop is **read → detect → propose chunk-by-chunk → apply confirmed → summarize**. The documenter skill's *Pattern A — User-described change* is the procedural template; this command supplies the *what to check for* (the canonical structure) and the placement defaults.

### Phase 1 — Read

Read the full `CLAUDE.md`. Note: line count, top-level headings (`#` and `##`), and any blockquote that looks like a previously-installed orientation reference.

### Phase 2 — Detect

The canonical devkit-compliant `CLAUDE.md` has six elements, in this order:

| # | Element | Recognition cue |
|---|---|---|
| 1 | **Title** — h1 with the project name | First non-blank line is `# <something>`. |
| 2 | **One-line description** — short paragraph immediately after the title | Non-blank line(s) after the h1, before the first `##`. |
| 3 | **`## How to read this project`** — explains the two sources of truth (`docs/` vs `.claude/state.md`) | An `##` heading named "how to read" / "orient" / "navigation" / similar, AND content mentions both `docs/` and `.claude/state.md`. |
| 4 | **Orientation reference blockquote** — `> **devkit pack:** see \`.claude/devkit-orientation.md\` for ...` | A blockquote anywhere in the file containing the literal string `.claude/devkit-orientation.md`. Exact wording may drift between pack versions; presence of the path is the test. |
| 5 | **`## Project conventions`** — section the user fills with project-specific load-bearing rules | An `##` heading named "Project conventions" / "Conventions" / "Setup" / "Stack" / similar, holding language/runtime/test-runner/style/branch-naming content. |
| 6 | **`## When in doubt`** — orientation pointer with a numbered list of "read X first" steps | An `##` heading named "When in doubt" / "Getting started" / "Orientation" / similar, containing an ordered list pointing at `.claude/state.md` and the active spec. |

Classify each element:

- **Present (exact).** Element exists at the expected place with content that satisfies the canonical role. No change proposed.
- **Present (equivalent).** Element exists under a different heading or in a different location but conceptually covers the role. Name the existing section in your finding; default to leaving as-is unless the equivalence is partial. Gratuitous heading renames create churn — propose them only if the user benefits from canonical naming (e.g., they're new to devkit and the heading is significantly misleading).
- **Partial.** Some of the canonical content is present, some is missing. Propose adding only what's missing; do not rewrite what's there.
- **Absent.** No equivalent exists. Propose adding it at the canonical position (see *Placement defaults* below).

### Phase 3 — Propose chunk-by-chunk

**Placement defaults.** Use these when proposing additions (override only if the existing file's structure makes a different placement obviously better):

- **Orientation reference (4)** — between the description (2) and the first existing `##` heading. If there's no description, immediately after the title. **Never at the bottom** — the reference is orientation content; it belongs near the top where it's read first.
- **`## How to read this project` (3)** — directly after the orientation reference. Together they form the orient block.
- **`## Project conventions` (5)** — after the orient block, before any user-authored content sections. If the user has a `## Setup` or `## Stack` section that covers similar ground, propose equivalence rather than adding a duplicate.
- **`## When in doubt` (6)** — last `##` heading in the file. End-of-file is the conventional spot for a closing-pointer section.

**Proposal shape.** For each element classified as partial or absent (and equivalent elements where you're proposing a non-trivial reconciliation), produce a proposal of this shape:

````markdown
**Element <N>: <name>** — <classification>

<one-sentence finding: what's there, what's missing>

Proposed change:
```diff
+ ## <heading>
+
+ <content>
```

Placement: <where the diff lands — line number or "after section X" / "end of file">.

Accept / modify / skip?
````

Surface proposals **one at a time** (or as a small batch of 2–3 when tightly coupled — e.g., elements 3 and 4 together as the orient block). Wait for the user's call on each before moving on. The documenter cardinal discipline holds: never apply a proposal silently, and never bundle so many proposals at once that the user can't review each.

For an **equivalent** classification where the proposal is "leave as-is," surface as informational only:

```markdown
**Element <N>: <name>** — present (equivalent)

You have `## Setup` (line 23) covering this role. Content is materially equivalent to the canonical "Project conventions" section. Leaving as-is.
```

Informational items don't need confirmation. The user can override (request a rename or restructuring) by saying so.

### Phase 4 — Apply

For each accepted proposal, edit `CLAUDE.md` to apply it. Use `Edit` for precise insertions; do not rewrite the whole file. Preserve user-authored content exactly — only the six canonical structural elements are in scope for this command.

If the user modified a proposal (e.g., "yes but use 'Stack' instead of 'Project conventions' as the heading"), apply the modified version. If the user skipped a proposal, do not apply it; note the skip for the summary.

### Phase 5 — Summarize

End with a short summary in this shape:

```markdown
CLAUDE.md merge complete.

Applied:
- <element> — <one-line description>
- <element> — ...

Skipped (by your choice):
- <element> — <reason if given>

Already present (no change):
- <element>

Equivalent (left as-is):
- <element> — <existing section cited>
```

If anything was skipped, end with a one-line nudge: "Re-run `/claude-md-merge` later to revisit skipped items."

Do not propose a git commit. CLAUDE.md edits are project housekeeping; the user commits at their cadence.

## Idempotency

Running `/claude-md-merge` twice in a row should produce no further changes the second time, assuming the first run's proposals were accepted (or skipped items remain skipped). If the second run surfaces new proposals, either:

- The first run's edits didn't apply cleanly (read the file directly to see what landed).
- The detection rules have a non-deterministic edge case — treat as a bug in this command.

A clean idempotent run on a compliant file produces:

```markdown
CLAUDE.md merge complete.

Already present (no change):
- Title
- Description
- How to read this project
- Orientation reference
- Project conventions
- When in doubt
```

## Halt conditions

Stop and surface, without applying anything, when:

- `CLAUDE.md` does not exist (precondition).
- `.claude/devkit-orientation.md` does not exist (precondition).
- The existing `CLAUDE.md` is in a format the canonical structure doesn't model (e.g., it's a stub redirecting to a different file). Surface the situation; do not force canonical structure on top.
- The user declines every proposed chunk in a row — they may prefer a different approach. Pause and ask whether to abandon the run.
- A proposal would touch user-authored content outside the six canonical elements. That's out of scope; surface and skip.

## What this command does not do

- **Does not touch `.claude/devkit-orientation.md`.** That file is pack-owned; the installer manages it.
- **Does not touch any other doc** (`docs/`, READMEs, etc.). `CLAUDE.md` only.
- **Does not commit.** The user commits at their cadence.
- **Does not rewrite user-authored content.** Project conventions, custom sections, prose the user wrote — all left alone. Only the canonical structural elements are in scope.
- **Does not require an active feature.** Unlike `/checkpoint` and `/feature-merge`, this command is project housekeeping and runs whether `.claude/state.md` shows an active feature or `none`.

## How this command plugs into the pack

- **`install.sh`** points at this command in two places: (a) the existing-CLAUDE.md prompt at fresh install ("decline and run `/claude-md-merge` for a structured merge"); (b) the TEMPLATE-CHANGED advisory at update mode ("run `/claude-md-merge` to walk a structured merge after the pack template changed"). The `--claude-md-only` install flag is the script-side equivalent for re-entering just the simple append path.
- **`documenter` skill** is loaded for the propose-before-writing discipline. This command's Phase 3 follows the skill's Pattern A shape.
- **No state.md interaction.** This command does not read or update `.claude/state.md`. It operates only on `CLAUDE.md`.
