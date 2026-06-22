# devkit pack — orientation

This file is **pack-owned**. It ships with the devkit Claude Code skill-pack and is overwritten on every pack update (with customization detection — if you edit it locally, the installer will skip it on update unless you pass `--force`). For project-specific conventions, edit `CLAUDE.md` at the project root instead. This file is referenced from `CLAUDE.md`; the model reads both when orienting.

## Memory layout

```
docs/
  specs/<feature>.md       what we're building (source of truth)
  plans/<feature>.md       how we're building it
  adr/NNNN-<name>.md       architecture decisions (immutable once accepted)
  domains/<domain>.md      living domain model
  summaries/<feature>.md   feature retrospectives (written at merge)
.claude/
  state.md                 active branch / feature / phase / pointers
  devkit-orientation.md    this file (pack-owned)
  skills/, agents/,        the devkit pack itself
  commands/, hooks/
  references/              checklists loaded on demand (SOLID, Clean Arch, security categories)
CLAUDE.md                  project index + project-specific conventions
```

Two sources of truth, addressed differently: `docs/` is human-first and durable (specs, plans, ADRs, domain models, retrospectives — read these for *what* and *why*); `.claude/state.md` is machine-first and current (active feature, branch, phase, spec — **read this first to orient**).

The engineering rules (TDD discipline, SOLID checklist, Clean Architecture layering, etc.) live in the pack's skills and are loaded automatically. This file does not repeat them.

## Workflow commands

The pack's five commands cover the standard six-phase software-delivery lifecycle (Define → Plan → Build → Verify → Review → Ship). `/build` covers both Build and Verify (per-step tester + verify substep); `/feature-merge` covers Review and Ship (three gates plus the merge proposal). The command names are the workflow vocabulary; this paragraph exists for cross-framework orientation only.

Available now:

- **`/feature-start "<short description>"`** — begin a feature. PM skill brainstorms with you (visible, interactive); proposes a domain decomposition; invokes the architect subagent for genuinely architectural questions; drafts a typical-depth spec at `docs/specs/<slug>.md`; creates `feature/<slug>` branch; updates state.md to `Phase: spec-draft`. You review and approve the spec by flipping its front-matter `status` from `draft` to `approved`.

- **`/plan`** — convert the approved spec into an implementation plan. PM and engineer skills together produce a research-grounded plan with conventions, per-step type signatures for the tester, and acceptance-criteria mapping. Architect may be invoked when research surfaces a first-of-kind cross-cutting decision. Writes `docs/plans/<slug>.md` with `status: draft`; updates state.md to `Phase: plan-draft`. You review and approve by flipping the plan's front-matter `status` to `approved`.

- **`/build`** — execute the approved plan under TDD. Reads `.claude/state.md` for the active feature and plan. Loops per plan step: tester subagent writes failing tests in fresh context → engineer writes implementation to green → SOLID + Clean Architecture checks → state.md updated. One `/build` invocation completes one step and pauses.

- **`/checkpoint <description>`** — mid-feature doc-sync and amendments. Loads the documenter skill to propose (never silently apply) changes to specs, plans, ADRs, and state.md. Three modes: with a description (amendment), `/checkpoint park` (park the feature without merging), or no args (interactive: ask what changed or run a lightweight drift-reconciliation pass).

- **`/feature-merge`** — close out a feature. Three gates in fixed order: (1) tests pass; (2) docs reconciliation (Pattern D + acceptance-criteria coverage); (3) security review by the `security-reviewer` subagent in fresh context. On success, documenter writes `docs/summaries/<feature>.md`, updates domain docs if applicable, marks any parked features as superseded, proposes the merge mechanics, waits for user confirmation, then clears state.md. Halts on any gate failure; merge is always proposed (never auto-executed).

### Housekeeping commands

Project-housekeeping commands run outside the feature lifecycle. No active feature required.

- **`/adopt [<area>]`** — bootstrap durable memory when an existing codebase adopts the pack. Surveys conventions (with file:line evidence) into `CLAUDE.md`'s *Project conventions*; discovers and confirms the existing domain map; writes terse baseline `docs/domains/<domain>.md` docs (each with an *as-built rationale* subsection); and — only for decisions you flag as load-bearing *and* reversible — writes ADRs. Propose-before-write throughout; `state.md` stays idle. Incremental and idempotent: the first run documents the spine, re-runs propose deltas, and an optional `<area>` scopes the pass to one subsystem. Run it once after install on a mature project, before your first `/feature-start`. Greenfield projects don't need it — memory grows feature by feature.

- **`/claude-md-merge`** — interactive reconciliation between the project's `CLAUDE.md` and the canonical devkit-compliant structure (title, description, *How to read this project*, orientation reference, *Project conventions*, *When in doubt*). Detects sections that are present, semantically equivalent under a different heading, or partial; proposes section-by-section merges via the documenter skill's *propose before writing* discipline. Idempotent — a clean run on a compliant file reports "nothing to merge." Use after declining `install.sh`'s append prompt, after a pack update changed the template, or anytime an existing `CLAUDE.md` has overlapping content the installer's one-line append can't handle thoughtfully.

## Commit cadence

Each workflow command proposes its own commit before pausing; you confirm or decline. Approval-status flips (`draft → approved`) are user-driven and get their own commits between commands. The full cadence for a feature, end to end:

| Moment | Trigger | Typical commit message |
|---|---|---|
| Spec drafted + branch created (+ any first-pass ADRs) | end of `/feature-start` | `spec: <slug> (draft)` |
| Spec approved | you flip front-matter `status` to `approved` | `approve spec: <slug>` |
| Plan drafted (+ any architect ADRs) | end of `/plan` | `plan: <slug> (draft, <N> steps)` |
| Plan approved | you flip front-matter `status` to `approved` | `approve plan: <slug>` |
| Each plan step | end of `/build` (engineer Verify substep 5) | `step N: <step heading>` |
| Each amendment | end of `/checkpoint` | `/checkpoint A: <description>` (or B/C/D variant) |
| Summary + domain doc + state.md transition | inside `/feature-merge` | `/feature-merge: summary + state.md to idle` |
| Merge to mainline | end of `/feature-merge` (your confirmation) | `Merge feature/<slug> into <mainline>` |

Two rules apply everywhere:

- **Stage explicitly.** Each command lists which files it expects to commit; pass those paths to `git add` directly. Never `git add -A` / `git add .` — that picks up untracked detritus like `__pycache__/`, sqlite sidecar files, IDE state, etc. that the project's `.gitignore` may not yet cover.
- **Propose, never silent.** Every commit moment above is a proposal you can decline. Declining is a legitimate signal (review further, batch, or amend the plan via `/checkpoint`). What the pack never does is commit silently or skip the proposal entirely.

A clean feature history reads as one line per logical moment — bisectable, revertable per step. A feature that landed in one mega-commit ignored the cadence; the next feature is a chance to course-correct.

## Automated guards

- **`doc-drift-detector` hook** (`PostToolUse`) — fires after every `Edit`, `Write`, `NotebookEdit`, or `MultiEdit` tool call. Reads the active feature's spec front-matter `owned_files` globs from `.claude/state.md`; if the edited file path matches no glob, surfaces a warning so the model can address it. Does not block; warning is informational. Resolution: amend the spec's scope via `/checkpoint <description>` if the edit belongs in the feature, or move the change to a different feature.

  Install: copy `pack/hooks/doc-drift-detector.py` to `.claude/hooks/` and merge the snippet from `pack/hooks/settings.json.fragment` into `.claude/settings.json`. The script requires only Python 3 stdlib. The devkit installer (`install.sh`) handles all of this automatically.

  Built-in exclusions: `.claude/**`, `docs/**`, `CLAUDE.md`, `README.md`, common build manifests (`pyproject.toml`, `package.json`, `Cargo.toml`). Edits to these never trigger drift — the documenter skill amends them as part of normal `/checkpoint` work.
