# devkit

A Claude Code skill-pack that enforces a specific engineering shape on a project: spec-first feature work, TDD-driven implementation, branch-per-feature with three closeout gates (tests → docs reconciliation → security review), and living documentation that the pack keeps current via a `PostToolUse` drift-detection hook.

It composes Claude Code's native primitives — subagents, skills, slash commands, hooks, `CLAUDE.md` — rather than building a parallel framework. Nothing here re-implements what Claude Code already does.

## Status

**v0.x — feature-complete, lightly dogfooded.** All six core slices are written and have been exercised end-to-end on one project ([chungar](#dogfood-target)). A seventh "commit discipline" polish pass landed afterward and is not yet dogfood-validated. The pack works today for someone who reads through this README and the design docs; it has not yet been installed by a stranger on a fresh second project, which is the real "stands on its own" test. Treat it accordingly.

The honest caveats:

- One-project dogfood. Behavior on radically different stacks (non-Python, Windows, monorepos, etc.) is unverified.
- Slice-7 commit-proposal substeps haven't been exercised by a real `/build` invocation yet.
- Install scripting is new (this release); the manual install path the chungar dogfood used is what's actually battle-tested.
- A handful of polish items are tracked in the design notes (see `docs/validation/slice-6.md` Findings 5–7); they don't block use, but they're real.

## Requirements

- **Claude Code** (CLI, desktop, or IDE extension — anything that loads `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, and `.claude/hooks/`).
- **Python 3** — the drift-detection hook is stdlib-only Python.
- **Bash** — the installer is a bash script.
- **git** — every workflow command assumes a git repo with a mainline branch (`main` or `master`).

## Install

```bash
git clone <this-repo>
cd <this-repo>
./install.sh /path/to/your/project --project-name "your-project" --description "One-line description."
```

Flags:

- `--project-name NAME` — fills `{{PROJECT_NAME}}` in `CLAUDE.md` (default: target dir basename).
- `--description TEXT` — fills `{{ONE_LINE_PROJECT_DESCRIPTION}}` (default: a placeholder you're prompted to edit).
- `--mainline BRANCH` — overrides auto-detected default branch.
- `--force` — in update mode, overwrite locally-modified files (with backup).
- `--dry-run` — show the plan and exit without writing.

Target dir defaults to the current directory if omitted. The script is idempotent — re-running it on an already-installed target switches to update mode (see below).

### What `install.sh` does (fresh install)

1. Copies `pack/{skills,agents,commands,hooks}/*` into `<target>/.claude/`.
2. Copies `pack/devkit-orientation.md` into `<target>/.claude/devkit-orientation.md` (pack-owned reference doc; see below).
3. Sets the executable bit on `.claude/hooks/doc-drift-detector.py`.
4. Merges `pack/hooks/settings.json.fragment` into `<target>/.claude/settings.json` (creates it if missing; otherwise appends the hook entry without duplicating).
5. Copies `pack/state.md.template` to `<target>/.claude/state.md` — **only if missing** (won't clobber an active project state).
6. Handles `<target>/CLAUDE.md` (see the next subsection for the three cases).
7. Appends `__pycache__/` and `*.pyc` to `<target>/.gitignore` if absent.
8. Writes `<target>/.claude/.devkit-manifest.json` (file hashes for future-update planning) and `<target>/.claude/.devkit-version`.

After install, edit `CLAUDE.md`'s `{{LIST_PROJECT_CONVENTIONS_HERE}}` slot with your project's load-bearing conventions (language + version, test runner, framework, style rules, branch naming).

### How `CLAUDE.md` is handled

The pack's bulky orientation content (workflow commands, memory layout, commit cadence, automated guards) lives in **`.claude/devkit-orientation.md`** — a pack-owned file that updates with each pack version. `CLAUDE.md` itself stays small and project-owned, and only needs a one-line reference to the orientation file so Claude Code loads it during memory orient.

The installer handles three cases on fresh install:

| Case | Behavior |
|---|---|
| No existing `CLAUDE.md` | Stamp the slim `CLAUDE.md.template` (title + description + conventions slot + orientation reference + "when in doubt" pointer). |
| Existing `CLAUDE.md`, reference already present | Leave untouched. |
| Existing `CLAUDE.md`, reference missing | Print the recommended one-line reference and **ask** whether to append it to the end of your `CLAUDE.md`. Accept ⇒ appended. Decline ⇒ left alone with a next-steps reminder to add it manually. |

The reference line itself:

```markdown
> **devkit pack:** see `.claude/devkit-orientation.md` for the pack's workflow commands, memory layout, commit cadence, and automated guards.
```

Future pack updates rewrite `.claude/devkit-orientation.md` automatically (with customization detection — see the update mode section below). Your `CLAUDE.md` is never re-touched after install.

### Updating to a new pack version

When the pack moves to a new version, re-run the install script against the same target:

```bash
cd /path/to/devkit && git pull
./install.sh /path/to/your/project --project-name "your-project"
```

The installer detects the existing `.devkit-manifest.json` and switches to **update mode**: it computes a per-file plan, shows you a summary (counts + new/updated/skipped lists), then asks for confirmation before writing.

| Plan verb | Meaning | Default action |
|---|---|---|
| `UPDATE`    | File exists in target; matches what we installed; safe to overwrite with new pack version. | overwrite |
| `NEW`       | File doesn't exist in target (added in this pack version). | install |
| `SKIP`      | File exists in target but differs from what we installed — you customized it. | leave alone (pass `--force` to overwrite, with backup to `.claude/.devkit-bak/`) |
| `UNCHANGED` | Target file already matches the new pack — no-op. | nothing |

Templates (`CLAUDE.md.template`, `state.md.template`) are **never auto-overwritten**. If they changed between your installed version and the current pack, the installer surfaces an advisory with a `diff` command you can run to see what's new, then you merge by hand.

Use `--dry-run` first if you want to see exactly what would change before committing.

### Manual install fallback

If the script doesn't fit your environment, copy `pack/skills/*`, `pack/agents/*`, and `pack/commands/*` into the target's `.claude/` subdirectories; copy `pack/hooks/doc-drift-detector.py` to `.claude/hooks/` and `chmod +x` it; create or merge `.claude/settings.json` from `pack/hooks/settings.json.fragment`; copy `pack/state.md.template` to `.claude/state.md`; and start `CLAUDE.md` from `pack/CLAUDE.md.template`. Skipping the manifest is fine; you just lose customization detection on future updates.

## What you get

| Component | Purpose |
|---|---|
| **Skills** (`pack/skills/`) | `pm` (brainstorm-to-spec discipline + plan-time research), `engineer` (TDD loop + SOLID/Clean Arch + commit cadence), `documenter` (amends specs/plans/ADRs/state.md; authors summaries at merge) |
| **Subagents** (`pack/agents/`) | `architect` (fresh-context architectural recommendations + ADR drafts), `tester` (fresh-context red-phase test authoring), `security-reviewer` (fresh-context security pass at merge) |
| **Slash commands** (`pack/commands/`) | `/feature-start`, `/plan`, `/build`, `/checkpoint`, `/feature-merge` — one per workflow lifecycle phase |
| **Hook** (`pack/hooks/`) | `doc-drift-detector.py` — `PostToolUse` warning when an edit touches files outside the active feature's `owned_files` glob |
| **Orientation doc** (`pack/devkit-orientation.md`) | Pack-owned reference: memory layout, workflow commands, commit cadence, automated guards. Installs to `.claude/devkit-orientation.md`; auto-updated; referenced from your `CLAUDE.md`. |
| **CLAUDE.md template** | Project-side: title, description, project-specific conventions slot, "when in doubt" pointer + one-line reference to the orientation doc. Slim — most pack content lives in the orientation doc, not here. |

## Workflow walkthrough

A complete feature, end to end:

1. **`/feature-start "<short description>"`** — The `pm` skill brainstorms with you (visible, interactive), proposes a domain decomposition, drafts a typical-depth spec at `docs/specs/<slug>.md`, creates a `feature/<slug>` branch, and updates `.claude/state.md`. Invokes the `architect` subagent if a brainstorm surfaces a real architectural question. Proposes a commit (`spec: <slug> (draft)`) before pausing.
2. **Approve the spec.** You flip the spec's front-matter `status` from `draft` to `approved` and commit that change yourself (`approve spec: <slug>`).
3. **`/plan`** — `pm` + `engineer` skills together produce a research-grounded implementation plan at `docs/plans/<slug>.md` with repo-specific conventions (cited file:line), per-step type signatures for the tester, and an acceptance-criteria mapping table. Architect runs again if first-of-kind cross-cutting patterns surface. Proposes a commit (`plan: <slug> (draft, N steps)`) before pausing.
4. **Approve the plan.** Same shape as spec approval: flip `status` to `approved`, commit (`approve plan: <slug>`).
5. **`/build`** — Executes one plan step under TDD discipline. The `tester` subagent writes failing tests in fresh context; the `engineer` brings them green; SOLID + Clean Arch checks run per diff; `state.md` is updated; a commit is proposed for the step (`step N: <heading>`). Repeat for each plan step.
6. **`/checkpoint`** (optional, mid-feature) — When something needs amending: `/checkpoint <description>` for a user-described change, `/checkpoint park` to park the feature, or `/checkpoint` with no args for a drift-reconciliation pass. The `documenter` proposes (never silently applies) the amendment; on confirm, applies and proposes a commit.
7. **`/feature-merge`** — Three gates in fixed order: (1) full test suite green, (2) docs reconciliation + acceptance-criteria coverage, (3) `security-reviewer` subagent fresh-context pass. On success: `documenter` authors `docs/summaries/<slug>.md`, updates `docs/domains/<domain>.md` if applicable, marks any superseded parked features, then proposes the merge mechanics and waits for your explicit confirmation before any git history change.

The full commit cadence is documented in `CLAUDE.md`'s "Commit cadence" section after install.

## Memory layout

The pack distinguishes **durable** docs (human-readable, live in git, evolve slowly) from a **working pointer** (machine-readable, updated constantly, cleared at merge):

```
docs/
  specs/<feature>.md          what we're building (one per feature, lifecycle: draft → approved → merged)
  plans/<feature>.md          how we're building it (one per feature, lifecycle ditto)
  adr/NNNN-<name>.md          irreversible architectural decisions (immutable once accepted)
  summaries/<feature>.md      feature retrospectives (one per merged feature)
  domains/<domain>.md         living domain vocabulary (one per bounded context)

.claude/state.md              active feature, branch, phase, spec/plan paths, parked features
```

Specs answer *what*, plans answer *how*. ADRs are immutable once accepted (supersede with a new ADR if needed). Summaries are written at merge; treated as history within a few days. Domain docs evolve slowly with the project. `state.md` is the working pointer the slash commands read and update.

## Three disciplines worth understanding

These are the patterns that show up everywhere in the pack:

- **Propose before writing.** The `documenter` skill never silently applies a doc edit. The `engineer` skill never silently commits. The `/feature-merge` command never auto-executes the merge. Every durable change is a proposal you confirm; declining is always legitimate. This is the cardinal discipline.
- **Fresh context for adversarial work.** The `tester`, `architect`, and `security-reviewer` all run as subagents in fresh context. This is load-bearing: a tester that absorbed the implementer's rationale produces sympathetic tests; a security-reviewer who sat through the build conversation produces sympathetic findings. Fresh context produces independent eyes.
- **Three-layer doc-currency defense.** The `doc-drift-detector` hook catches drift at the moment of edit. `/checkpoint` (no args) runs an on-demand reconciliation pass. `/feature-merge`'s Gate 2 runs a final-pass reconciliation. All three layers cooperate; none alone is sufficient.

## Uninstall

```bash
rm -rf <target>/.claude
# Optionally: revert CLAUDE.md, .gitignore additions, and docs/{specs,plans,adr,summaries,domains}/
```

The pack does not modify your source code. Removing `.claude/` removes all skills, commands, subagents, hooks, and state. Generated documentation lives in `docs/` and is yours to keep or delete.

## Going deeper

Read the design docs in `docs/design/` if you want the rationale:

- `0001-skill-pack-architecture.md` — the architecture and why this synthesis.
- `comparison-table.md` — why this instead of extending Superpowers, SpecKit, or GSD.
- `walkthrough.md` — what a feature looks like end to end.
- `inventory-and-build-order.md` — the slice-by-slice build plan that produced the pack.

Per-slice validation reports in `docs/validation/` document what was exercised and what surfaced during dogfood.

## Dogfood target

The pack was built incrementally and dogfooded on [chungar](https://github.com/rubrikinc/rubrik-chungarsih-agent) (a Google ADK + LiteLLM personal-assistant agent). Slices 1 through 6 were validated by shipping one feature (`notes-write-and-delete`) end-to-end. Slice 7 (commit-discipline polish) was triggered by the follow-up feature's mega-commit failure mode and is still pending dogfood validation.

## License

(Add a LICENSE file if you intend to publish.)
