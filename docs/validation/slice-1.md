# Slice 1 — Dogfood Validation Report

**Slice:** 1 (minimum viable TDD loop)
**Dogfood target:** chungar (`/Users/bryanlorette/Code/rubrik-chungarsih-agent`)
**Validation feature:** `read_note` + `search_notes` tools, sqlite-backed
**Status:** complete (pivot at Step 1 of 5 — see "Verdict" section for rationale)
**Date:** 2026-05-29

## Executive summary

Slice 1's pack content (engineer skill, tester subagent, `/build` command, memory-layout templates) worked when exercised end-to-end on one real plan step. The TDD loop ran cleanly: tester subagent wrote 12 failing tests in fresh context, engineer wrote a 50-line implementation that brought all 12 to green, SOLID + Clean Arch review produced no changes, state.md update + git commit closed the step.

The high-value findings are not about the pack content. They are about the **artifact templates** the walkthrough demonstrates (Findings 1, 2) and about the **plan-time research process** (Finding 3). Both surface as "the walkthrough's examples are minimum-viable demonstrations, not exemplars" — and both need to be addressed before slice 2 authors the `pm` skill, because the `pm` skill will encode the spec/plan templates the walkthrough currently models.

The pack as authored is shippable for the TDD loop. The pre-slice-2 revisions named below are the work required to make slice 2's authoring start from a corrected baseline.

## Findings

### Finding 1 — Walkthrough's spec template is too thin for real features

**Surface:** During spec authoring for `notes-read-and-search`. The initial spec, written by following the walkthrough's example shape, came in at ~70 lines and was flagged by the user as "on the light side."

**Root cause:** The walkthrough example (`docs/design/walkthrough.md`) demonstrates the artifact's existence and rough shape but elides the detail a real spec needs: data model, tool contract (return shapes including not-found / empty), error handling, file-by-file layout, integration/wiring, testing strategy per layer, risks. Following the example produced a minimum-viable spec, not a typical one.

**Impact:** A thin spec defers decisions into the plan and the tests, which is the failure mode spec-first is supposed to prevent. The amended spec (~190 lines) caught several decisions that would otherwise have been made implicitly during /build (limit clamping, empty-query handling, schema column types, factory wiring pattern, when sqlite errors propagate vs structured-result).

**Recommended changes (for slice 2 / before pack ships):**
- Update `docs/design/walkthrough.md`'s spec example to model the richer shape.
- When the `pm` skill is authored in slice 2, encode the richer spec template as the default — including the section checklist (data model, tool contract, errors, layout, wiring, testing, risks).
- Hold thin sections explicitly ("No persistence — no schema section") rather than silently omitting them. Makes the cuts visible.

### Finding 2 — Walkthrough's plan template is too thin in the same way

**Surface:** During plan authoring for `notes-read-and-search`. The first plan draft, written by following the walkthrough's plan example, came in shorter than the spec and was flagged as "on the lite side" — specifically for missing the **code-standards-of-the-repo** layer.

**Root cause:** The walkthrough's plan example shows test lists, file paths, and ordering — but elides the layer that bridges *generic best practice* and *this repo's actual code*: existing import style, framework-specific idioms (e.g., how ADK actually accepts tools), Pydantic-v2 patterns the repo prefers, module sizing, what's a project-first. The plan I wrote had the same shape as the example and was therefore plausibly correct but stylistically detached from chungar.

**Impact:** Without repo-grounded plans, generated code is "technically correct" but foreign to the project. Symptoms would include: choosing `aiosqlite` when stdlib sync `sqlite3` matches the framework (ADK detects sync/async automatically; no need for async I/O); choosing absolute imports in a package that uses relative; using class-arg Pydantic v2 shorthand in a repo that prefers explicit `model_config = ConfigDict(...)`. Each is invisible until the diff lands and someone has to re-style it.

**Recommended changes:**
- The plan-drafting flow needs an explicit research phase: read the repo, inspect the framework where behavior matters, write down the conventions, *then* draft the plan.
- Surface the research either as a top-level "Conventions and constraints" section in the plan, or per-step notes that name the file/pattern being followed, or both.
- Update `docs/design/walkthrough.md`'s plan example to model the richer shape.
- When the `pm` / `engineer` skills are extended for slice 3 (`/plan`), encode "research-first plan drafting" as a required step — not optional.

This finding is a near-mirror of Finding 1: the walkthrough's artifact examples are minimum-viable demonstrations, not exemplars. Both the spec and the plan templates need a beef-up.

### Finding 3 — Plan-time research missed a cross-step prerequisite hidden in package `__init__.py`

**Surface:** During Step 1 `/build` simulation. Tests for `chungar.notes.domain` fail at collection time with `ModuleNotFoundError: No module named 'config'`. The chain is: importing `chungar.notes.domain` triggers `chungar/__init__.py:1: from . import agent`, which triggers `chungar/agent.py:3: from config import ChungarConfig` (broken — should be relative `.config`).

**Root cause:** The plan deferred the `agent.py` import fix to Step 5 (agent integration), reasoning that "the fix is needed when we wire tools onto `root_agent`." That reasoning ignored a structural fact: `chungar/__init__.py` eagerly imports `agent`, so **any** import path through the `chungar` package triggers the broken line. Step 1's tests can't even reach the red state without the fix.

**The plan-time research** (Pydantic conventions, ADK constraints, repo conventions) looked at config patterns, ADK source, and the `chungar/__init__.py: from . import agent` line individually — but didn't compose them to predict the import-chain blocker. A research checklist that included "run a smoke `python -c 'import <package>.<submodule>'` for each step's added module" would have caught this in 30 seconds.

**Impact:** Plan needs amending mid-feature. The natural escalation path is `/checkpoint` (slice 4), which doesn't exist yet, so the user is interrupted manually. Real /build sessions will hit this category of issue regularly; slice 4's `/checkpoint` is doing more load-bearing work than it might appear.

**Recommended changes:**
- Add to the engineer-skill's "verify" or "before red" preconditions: `python -c 'import <package>.<submodule>'` smoke-import for any submodule the step will touch, run *before* the tester is invoked. Catches dead-package-init issues early.
- When the `/plan` command (slice 3) is authored, add a research-time check that each step's "new files" can be imported assuming all earlier steps are done. Static analysis of existing `__init__.py` files counts.
- Until `/checkpoint` ships, the engineer skill's "stop and ask" path should be the documented escalation for this category. (Currently it is, per the skill content. Good.)

### Finding 4 — Spec/plan minor inconsistency surfaced by the tester subagent

**Surface:** Tester subagent (Step 1 invocation) flagged that the spec describes `id` as "format is UUID string (validated as `str`, not coerced to `UUID`)" while the plan's test list only requires non-empty validation. The tester correctly **did not** add a UUID-format test (test list is authoritative); it flagged the divergence and continued.

**Root cause:** Spec was richer than the plan's test list. Plan derivation translated some spec requirements into tests but not this one.

**Impact:** Minor — the implementer (me) now decides whether to enforce UUID format. But it's evidence that the spec → plan derivation is a quiet place where information can drop. When `/plan` is authored (slice 3), the derivation step should explicitly checklist each spec requirement and either generate a test or note a deliberate omission.

**Validation of the tester subagent behavior itself:** the subagent's "flag missing behaviors, don't add tests" discipline kicked in correctly. The fresh-context property (preserved via the Agent tool's general-purpose subagent) worked as designed — the tester saw only the spec, plan, type signatures, and project context, never implementation source.

### Finding 5 — Engineer skill's TDD loop worked end-to-end (positive signal)

**Surface:** Step 1 simulation completed cleanly once Finding 3's blocker was resolved. Loop: invoke tester (fresh context via Agent tool) → place returned tests → run pytest, confirm red → write 50-line `domain.py` implementation → run pytest, confirm 12/12 green → SOLID + Clean Arch review (no changes needed; already minimal) → update state.md → commit.

**What worked:**

- **Fresh-context guarantee** held. Tester saw only spec + plan-step + type signatures + project conventions, never any implementation source (none existed yet anyway, but the principle was preserved).
- **Tester's "flag, don't add" discipline** kicked in correctly for the UUID-format spec/plan inconsistency (Finding 4).
- **"Minimum implementation"** rule held — the engineer wrote exactly what the 12 tests required; no speculative scope.
- **State.md update + commit** felt natural at the end of the step; no friction.
- **Tester self-scoped its task tracking** ("Task tracking is the engineer's concern, not the tester's") — small but nice signal that the subagent prompt's role boundary is clear.

**What was noisy:**

- The pause-between-steps rule felt right here because Finding 3 surfaced a real decision. In a step that runs cleanly, the discipline would feel more bureaucratic. Worth watching across more steps.
- Authoring the implementation took noticeably less time than reasoning about what `model_config = ConfigDict(...)` flag combination would satisfy each test. The hard work was choosing the right combination of `frozen`, `strict`, `str_strip_whitespace`, `Field(max_length=...)`, `field_validator`, and `model_validator`. The plan's conventions table helped a lot — without it, the implementation would have drifted to class-arg shorthand or inconsistent validation styles.

## Validation feature progress

- [x] Chungar prep (pyproject, pytest, dirs, git init, baseline commit)
- [x] Pack installed into `chungar/.claude/` (skills, agents, commands, state.md, CLAUDE.md filled)
- [x] Spec drafted, beefed up, approved (`docs/specs/notes-read-and-search.md`)
- [x] Plan drafted, beefed up, approved (`docs/plans/notes-read-and-search.md`)
- [x] Feature branch + state.md pointing at plan
- [x] Step 0 (amendment) — `chungar/agent.py` import fix + `chungar/__init__.py` emptied
- [x] Step 1 — Domain types: 12/12 tests green, committed on feature branch
- [ ] Step 2 — Application port + service: **deferred** (validation pivot — see Verdict)
- [ ] Step 3 — Sqlite adapter: **deferred**
- [ ] Step 4 — Tool layer + factory: **deferred**
- [ ] Step 5 — Agent integration: **deferred** (import-fix portion already done in Step 0)

## Verdict

**Slice 1 passes with required pre-slice-2 revisions.**

Rationale:

- **The pack content is validated for the TDD loop it claims to run.** Tester subagent's fresh-context constraint held, engineer skill's red/green/refactor/verify discipline produced clean code, /build's preconditions caught the right preconditions, state.md's hybrid working-pointer model felt natural. The skill content matches the design.
- **The simulation stopped at 1 of 5 plan steps.** This is a deliberate pivot, not a failure. Steps 2–5 would have exercised the same loop on incrementally more complex code (port + service, sqlite adapter, tool layer, agent wiring). The marginal validation value drops sharply after step 1 — the loop is the loop. The risk worth flagging: edge cases in /build that show up only at multi-step distance (state.md handoff between steps, behavior when a step's red phase has cascading test failures) are unvalidated. Those should be surfaced in slice 2 or 3 dogfood on a multi-step feature.
- **Findings 1, 2, and 3 are real and must be addressed before slice 2.** Slice 2 builds the `pm` skill. The `pm` skill will encode the spec template. Authoring the `pm` skill against the current walkthrough's spec template would propagate the thinness systematically.
- **Finding 4 is a design hint for slice 3** (`/plan` command should checklist spec → plan derivation, not free-translate).
- **Finding 5 is the positive validation** the slice was authored to seek.

## Required pack revisions before slice 2 — COMPLETE (2026-05-29)

All four revisions landed in the same session as the dogfood:

1. ✅ `docs/design/walkthrough.md` — spec example (Phase 1) expanded to model the typical shape with Data model, Tool/API/user-flow contract, Error handling, Clean Architecture layout, Integration/wiring, Testing strategy, Risks, and expanded Acceptance criteria sections.
2. ✅ `docs/design/walkthrough.md` — plan example (Phase 2) expanded to include a Conventions and constraints section (repo conventions with cited evidence, project-firsts, framework constraints) and per-step "Conventions applied" subsections.
3. ✅ `pack/skills/engineer/SKILL.md` — added a new "Before red — smoke import" subsection to the TDD loop. Mirrored into `chungar/.claude/skills/engineer/SKILL.md` so the dogfood install stays in sync.
4. ✅ `docs/authoring-notes/spec-and-plan-depth.md` — written. Encodes the section checklists for both specs and plans, points at walkthrough demos + chungar real artifacts as exemplars, and gives slice 2 / slice 3 explicit guidance on what the `pm` skill and `/plan` command should encode.

Slice 2 is now authorable against a corrected baseline.

## Skill content gaps surfaced but deferred

These were noticed during dogfood and are worth tracking, but do not block slice 2:

- **Engineer skill is silent on commits.** The walkthrough mentions "committed-or-ready-to-commit" but the engineer skill doesn't prescribe a commit cadence or message style. In the dogfood we committed at the end of each step manually. Worth a small section in the engineer skill (or deferred until /feature-merge in slice 6 — which is when commits really matter).
- **State.md's `## Completed steps` section** was not in the template — /build adds it on first use. Consider seeding the section in `pack/state.md.template` so the structure is consistent from day one.
- **No install instructions for the pack.** Dogfood relied on manual `cp -R`. The pack needs a one-page install guide (or a script) before it ships beyond dogfood. Defer until pack is more complete.

## What was NOT validated

Honest list:

- Multi-step state.md handoff (steps 2 → 3 → 4 → 5 weren't run).
- Engineer skill's behavior when red tests pass on first run (the "stop and investigate" branch).
- Engineer skill's refactor branch (Step 1's implementation was already minimal; no refactor opportunity).
- Tester subagent's behavior when it's given partial implementation source (the "must not read" rule was vacuously satisfied because no implementation existed yet for Step 1).
- /build's behavior when state.md's `Next step` doesn't match a step in the plan.
- /build's behavior when the plan's front-matter `status` is anything other than `approved`.

The first three should be exercised in slice 2 or 3 dogfood. The last two are precondition tests worth adding to the engineer skill's content directly (no real dogfood needed; they're behavioral assertions on the skill itself).
