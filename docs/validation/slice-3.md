# Slice 3 — Dogfood Validation Report

**Slice:** 3 (plan generation — `/plan` command + plan-time behaviors on the `pm` and `engineer` skills)
**Dogfood target:** chungar (`/Users/bryanlorette/Code/rubrik-chungarsih-agent`)
**Validation feature:** `notes-write-and-delete` (continuation of slice-2 dogfood — same feature, taken through `/plan`)
**Status:** complete with two recommended pre-slice-4 revisions
**Date:** 2026-06-03

## Executive summary

Slice 3's pack content (plan-time extensions to `pm` and `engineer` skills, new `/plan` command) drove a real spec through to an approvable plan that's substantive (7 steps, ~530 lines) and grounded in observable chungar conventions cited file:line. The `/plan` command's halt-condition fired correctly mid-flow when research surfaced a load-bearing spec gap (the spec assumed read/search infrastructure existed; it didn't), forced a spec amendment, and resumed cleanly. Plan-time architect invocation also fired and produced ADR-0002.

The hardest signal from this dogfood is positive: **the research phase doesn't feel optional in practice.** Reading existing source (`chungar/notes/domain.py`, `chungar/config.py`, `chungar/agent.py`, ADK's `function_tool.py`, the parked plan) before drafting changed several plan decisions vs what I would have written from the spec alone — notably the timestamp serialization approach for tool outputs, the BEGIN IMMEDIATE transaction discipline, and the per-test-file fake pattern. All three would have surfaced as `/checkpoint` interruptions had the research phase been skipped.

Two pre-slice-4 revisions are recommended; both are small. The pack is otherwise shippable for slice 3.

## Findings

### Finding 1 — `/plan`'s halt-on-spec-gap fired and worked as designed

**Surface:** During Phase B (Research), reading `chungar/notes/` revealed only `domain.py` exists on the dogfood branch. The spec referred repeatedly to "existing" `NoteRepository`, `NoteQueryService`, `SqliteNoteRepository`, and `tools.py` — none of which existed. Two acceptance criteria (`After delete_note(id), read_note(id) returns not_found`; `The id returned by write_note is immediately resolvable by read_note`) were unimplementable without `read_note` existing.

**What worked:** `/plan` halted as designed. The halt condition language in `pack/commands/plan.md` ("Research surfaces evidence that the spec is internally inconsistent or names files/conventions that don't exist") fits exactly. The user was surfaced three resolution options (amend spec, build-on-assumption, cherry-pick more) and picked spec amendment.

**Spec amendment that resolved the halt:** added a `Prerequisites` section to the spec naming the parked-feature dependency and framing this slice as absorbing Steps 2–5 of the parked plan. Spec Domains-touched was updated to reflect "establish (in prerequisites) and extend (in new portion)." Plan then absorbed the read/search infrastructure as Steps 2–5 with write/delete steps layered on top.

**Positive signal.** This is exactly what `/plan` was designed to do: catch spec drift in plan-time research before it becomes "wrong code shipped." Slice-1's Finding 3 (the import-chain blocker discovered at `/build` time) was the same shape one slice later — research-time prevention vs build-time interruption.

**Small recommended change (worth tracking, not blocking):** the spec amendment was needed because the spec was authored against an assumed future state (read/search would land first). When `/feature-merge` (slice 6) eventually marks features superseded, the parked-feature dependency story should be cleaner — until then, plan-time amendments like this one are the workaround. Worth a forward-reference: `/feature-merge` should know how to mark a feature "superseded by X."

### Finding 2 — Research phase changed plan content in real ways

**Surface:** Research turned up three load-bearing facts that the spec didn't mention but the plan needed:

1. **Pydantic v2 `model_dump(mode="json")` produces ISO-8601 strings for nested `datetime` fields.** The spec said "tools return plain dicts with ISO-8601 timestamps." The plan's Step 6 implementation-notes captures `result.model_dump(mode="json")` as the cleanest approach, after noticing that the cherry-picked `Note` is a frozen Pydantic model — Pydantic's serialization mode handles the timestamp conversion natively. Without research, the plan likely would have said "manual `.isoformat()` on each timestamp," which works but doesn't compose with the discriminated unions added in Step 1.

2. **`Found` and `NotFound` (cherry-picked) don't carry a `status` literal field.** The spec assumes `DeleteNoteResult = Annotated[Deleted | NotFound, Field(discriminator="status")]`. For Pydantic's discriminated-union deserialization to work, `NotFound` must have `status: Literal["not_found"]`. The cherry-picked `NotFound` doesn't. Step 1's plan call-out notes this and folds the discriminator addition into the same step — minor scope expansion that would have surfaced as a `/checkpoint` mid-Step-1 had it not been caught at plan time.

3. **ADK `function_tool.py:290` uses `inspect.iscoroutinefunction` for sync/async detection.** The parked plan had this cited; my plan inherits the citation. Validation: reading the same file in `.venv/lib/python3.13/site-packages/google/adk/tools/function_tool.py` confirmed the line is still there in current ADK 1.28+. Sync `sqlite3` continues to be the right choice; this is a positive case of *re-confirming an inherited assumption* during research rather than blindly carrying it forward.

**Positive signal.** The pm skill's "research phase required" framing produces real plan-quality improvements. Each of these three would have shipped as an implicit decision (or a wrong one) had research been a nicety rather than a discipline.

**No change recommended.** This is exactly the slice-1 Finding 2 remediation working as intended.

### Finding 3 — Plan-time architect invocation worked; pm skill's cross-cutting cue caught it

**Surface:** Phase B research surfaced clock injection as a project-first that would set the pattern for every future write-side service. The updated pm skill's cross-cutting-pattern list (added in pre-slice-3 revisions) explicitly names "clock injection" and "transaction boundary" as cues. I invoked the architect via the documented Agent-tool fallback pattern (`subagent_type: general-purpose` + `architect.md` content in the prompt body).

The architect returned a substantive recommendation with full ADR draft. The recommendation correctly:
- Cited ADR-0001 as precedent ("write-side services own write-time concerns") and extended it.
- Explicitly rejected three alternatives (inline, domain factory, Clock Protocol) with reasoning specific to chungar's existing shape.
- Scoped applicability narrowly (write-side services that stamp time-derived fields; explicitly does *not* apply to read/query services, ADK tools, or anything in `domain.py`).
- Left the Clock-Protocol upgrade path open as "promote later when a second time-related capability appears."

**Positive signal.** The slice-2 pm-skill update worked: the cross-cutting-pattern cue caught clock injection in-flight rather than via post-hoc invocation. The Agent-tool fallback pattern continues to be operationally viable.

**Asymmetric judgment worth noting (Finding 3b):** I identified TWO architect-worthy cross-cutting patterns in research (clock injection AND WAL + BEGIN IMMEDIATE concurrency posture). I invoked the architect on clock injection only; WAL was documented as a project-first in the plan with rationale but not ratified by architect. The reasoning was: WAL's trade-offs were already explicitly committed in the spec brainstorm, the architect would mostly ratify, and a second architect call per plan adds friction.

**This is exactly the pm-skill discretion gap the slice-2 finding warned about.** The right behavior per the pm skill is "Default to invoking. Cheap insurance against silently baking a pattern into three steps." I exercised discretion to invoke once, not twice. That discretion may be defensible (WAL is genuinely lower-stakes given the spec's explicit commitment and the lack of a second sqlite-using feature to risk drift) but it's also exactly the failure mode the pm skill is trying to prevent. **Worth a pre-slice-4 revision to the pm skill:** clarify when invoking-twice-per-plan is correct vs when document-as-project-first-is-fine. Currently the skill says "default to invoking" without naming the cost trade-off or the appropriate threshold.

### Finding 4 — Plan length signals architect-vs-plan boundary erosion

**Surface:** The plan came in at ~530 lines for 7 steps. The Conventions and constraints section alone is ~70 lines with three substantive tables. Step entries are detailed (type signatures, test lists, conventions-applied bullets, why-this-order, SOLID notes — per the engineer skill's required-entries list).

The plan is dense because every required entry was filled. That's the design — slice-1 Finding 2 was that plans were too thin. But at 530 lines for 7 steps, a 15-step feature would produce a ~1200-line plan, which starts to be unwieldy.

**Observation:** the per-step type-signatures block is the largest per-step content. In the engineer skill's "Each step's required entries" list, type signatures are authoritative — the tester subagent needs them. But the plan also redundantly states those signatures in the Conventions and Step rationale, which inflates length without adding information.

**Recommended change (pre-slice-4, small):** the engineer skill's "Authoritative type signatures per step" section should note that the signatures block is the *single* source of truth — other parts of the step entry should reference back to it rather than re-iterating. Cuts redundancy at no information cost. This is a small wording tweak in the engineer skill, not a structural change.

**No change recommended on overall plan length.** Substantive specs produce substantive plans; that's the trade. If 1200 lines becomes uncomfortable for a 15-step feature, the right response is to question the feature decomposition, not the plan-template depth — break the feature into two smaller features each with its own spec + plan.

### Finding 5 — Acceptance mapping caught real coverage

**Surface:** The acceptance mapping table at the end of the plan covers every spec acceptance criterion. Building the table during Phase E forced me to confirm that each spec assertion has at least one step that satisfies it. Two criteria mapped to multi-step combinations I hadn't initially planned for:

- "Id returned by `write_note` is immediately resolvable by `read_note`" maps to Steps 5 + 6 (sqlite round-trip; e2e test through factory). Single-step mapping would have been wrong.
- "Second `delete_note(id)` returns `not_found` (not `deleted`)" maps to Steps 4 + 5 + 6 (service maps `False`→`NotFound`; sqlite returns `False`; e2e). Without acceptance mapping, this would have been "covered" by Step 4 alone, missing the sqlite + e2e validation.

**No criterion mapped to `—`.** No deliberate omissions surfaced for this spec; if they had, the discipline says to explain in the Note column. Worked as designed.

**Positive signal.** Slice-1 Finding 4 (the UUID-format coverage gap in the prior plan) is exactly the failure mode acceptance mapping prevents. The pm skill's new requirement to enumerate-then-fill-the-table catches gaps before the plan ships, not after.

### Finding 6 — `/build` precondition story works cleanly with `Phase` as descriptive

**Surface:** `/plan` writes `Phase: plan-draft` and the user is told to flip plan front-matter `status: draft → approved` to enable `/build`. `/build`'s precondition (re-reading `pack/commands/build.md`) checks the plan file's front-matter `status`, not state.md `Phase`. So the user only needs to edit one file (the plan) — state.md `Phase` is descriptive only.

This was a tiny worry during slice-3 authoring; pre-existing `/build` behavior turned out to already match. The build.md update to remove the slice-1-era manual-setup framing made the convention explicit.

**Positive signal.** Phase-as-descriptive is the right call. The alternative ("user must update state.md Phase too") would have created a two-edit approval gate with no behavioral benefit.

**No change recommended.**

### Finding 7 — Cherry-pick prep produced real friction the install story should address

**Surface:** Setting up the dogfood required cherry-picking the parked feature's Step 1 commit (`24c9682`) onto `feature/notes-write-and-delete`. The cherry-pick conflicted on `.claude/state.md` (HEAD's spec-draft view vs the cherry-picked building view) and brought along `__pycache__/*.pyc` files plus a `docs/plans/notes-read-and-search.md` modification — both unwanted.

Resolution required: `git checkout --ours .claude/state.md`, `git rm --cached -r */__pycache__`, `git restore --staged --worktree docs/plans/notes-read-and-search.md`, then `git cherry-pick --continue`. Three steps of git plumbing.

**This is operational friction that future dogfooders will hit.** The friction is real because:
- chungar lacks a `.gitignore` for `__pycache__` (will trip every Python project that hasn't gitignored bytecode).
- `.claude/state.md` is per-branch and naturally conflicts across feature transitions.
- Parked-feature commit hygiene (the pyc files getting committed by `git add -A` patterns) is a chungar issue, not a pack issue.

**Recommendations:**

- **For chungar (immediate, out of pack scope):** add `__pycache__/` and `*.py[cod]` to `.gitignore`. The next pack install commit on chungar should drop the existing tracked pyc files via `git rm`.
- **For the pack (forward-reference, slice 6 / install scripting):** the install guide should call out: (a) target project needs language-appropriate `.gitignore` entries before pack install, (b) `.claude/state.md` is per-branch by design, so cross-branch operations will conflict — that's a feature, not a bug, and shouldn't be resolved by sharing one state.md across branches.
- **For slice 6's `/feature-merge`:** "marking a feature superseded" should be a documented transition. Cherry-picking work between branches is honest but unwieldy; if `notes-read-and-search` had been "superseded by notes-write-and-delete" via the merge command, this dogfood's prep would have been a single command instead of three.

### Finding 8 — Engineer-skill plan-time content carried the weight without being heavy

**Surface:** The engineer skill's new "Plan-time behaviors" section (cardinal step-shape rule, Clean Arch dependency order, authoritative type signatures, smoke-import prediction) added ~80 lines to a previously-build-focused skill. All four sub-sections were directly applied during plan generation:

- **Cardinal step-shape rule** (green suite + revertable) shaped Step 5 (sqlite adapter doing all four operations in one step rather than splitting create/delete into separate steps, because splitting would duplicate connection handling and break revertability of either half independently).
- **Clean Arch dependency order** drove the 7-step sequence (domain → port → query-service → write-service → adapter → tools → wiring).
- **Type signatures per step** are present in every step; for the tester, they will be authoritative.
- **Smoke-import prediction** is noted in every step (each one says `python -c "import <module>"` should succeed before tester invocation).

**Positive signal.** The engineer skill's plan-time content earned its keep on first dogfood — each sub-section was applied, none was theoretical filler.

**Minor recommended change (per Finding 4):** the "Authoritative type signatures per step" subsection should explicitly say the signatures are the *single source of truth* (the rest of the step entry references but doesn't re-state).

## Validation feature progress

- [x] Slice-3 pack content authored (`pm` skill plan-time, `engineer` skill plan-time, `/plan` command) in `pack/`
- [x] `pack/commands/build.md` updated to remove slice-1-era manual-setup framing
- [x] `pack/CLAUDE.md.template` updated to list `/feature-start` and `/plan` as available commands
- [x] All mirrored into `chungar/.claude/`
- [x] Pack install committed on `feature/notes-write-and-delete` (slice-3 pack install committed in the feature branch; slice-2 install was on master)
- [x] Cherry-pick of `notes-read-and-search` Step 1 onto write-and-delete branch (clean after resolving state.md conflict + pruning pyc files)
- [x] Spec approval (front-matter `status: draft → approved`)
- [x] state.md transition (`spec-draft → spec-approved`)
- [x] `/plan` Phase A — Orient (read CLAUDE.md, spec, prior plan, ADRs, domain types, source samples)
- [x] `/plan` Phase B — Research (3 buckets: repo conventions with file:line cites, project-firsts, framework constraints from ADK source)
- [x] **`/plan` halt-on-spec-gap fired** — spec amendment loop ran (Prerequisites section added; Domains-touched updated)
- [x] `/plan` Phase B research re-completed against amended spec
- [x] `/plan` Phase C — Cross-cutting pattern check (clock injection invoked architect; WAL documented as project-first without invocation)
- [x] Architect returned recommendation + ADR-0002 draft via Agent-tool fallback pattern
- [x] ADR-0002 accepted and written; spec/plan front-matter updated to reference [1, 2]
- [x] `/plan` Phase D — Step decomposition (7 steps with all required entries)
- [x] `/plan` Phase E — Acceptance mapping (every spec criterion mapped; no `—` cells)
- [x] `/plan` Phase F — Plan written to `docs/plans/notes-write-and-delete.md` (status: draft); state.md updated to `plan-draft` with `Next step: Step 1 — Domain extensions`
- [x] `/plan` Phase G — Hand off (plan path, ADR path, branch name, approval prompt surfaced)
- [x] Plan committed on feature branch
- [ ] **NOT exercised in this dogfood:** `/build` execution against the approved plan. The slice-3 inventory description says dogfood should optionally include `/build` step 1. Skipped here to keep the slice-3 validation focused on plan-time content — `/build` exercise belongs to slice 1's loop, already validated separately.

## Verdict

**Slice 3 passes with two small pre-slice-4 revisions recommended.**

Rationale:

- **Pack content drove a real plan from a real spec.** Research phase produced substantive observations; cross-cutting pattern check caught one architect-worthy decision in-flight; acceptance mapping covered every criterion. Plan is 7 steps and ready for `/build`.
- **`/plan` halt-on-spec-gap was the strongest single signal** of the dogfood. The command's design caught a load-bearing inconsistency between spec and ground truth before plan content was written. That's the exact failure mode slice-1's Finding 3 surfaced one slice too late. Worked as intended.
- **The architect-invocation-judgment finding (Finding 3b)** is the one real gap: the pm skill says "default to invoking" but doesn't name the appropriate threshold or cost of double-invocation. The skill should either say "if in doubt, invoke for each" or articulate when bundling-or-skipping is appropriate.
- **Findings 1, 2, 5, 6, 8 are positive signals or document working-as-designed behavior.** Finding 7 names operational friction worth addressing in slice 6 / install scripting; not pack content.
- **The simulation did not exercise** plan approval (user flipping plan status to approved) or `/build` against the approved plan. Plan approval is a one-line user edit and not pack behavior. `/build` against this plan would exercise the multi-step state.md handoff that slice-1 left unvalidated; worth doing as part of slice-4 dogfood since that's where `/checkpoint` becomes the natural mid-build escape.

## Required pack revisions before slice 4

**Recommended:**

1. ⏳ Extend `pack/skills/pm/SKILL.md`'s "When to invoke the architect" section with explicit guidance on what to do when *multiple* cross-cutting patterns surface in one plan. The current section says "default to invoking" without addressing whether to invoke once-per-pattern, bundle, or apply judgment. Suggested addition: "When the same plan-time research surfaces multiple project-first patterns, invoke separately if each is genuinely cross-cutting and independent. Bundling questions into one invocation dilutes the recommendation; skipping the second invocation because the first ratified a *related* pattern is the failure mode this section exists to prevent." Mirror.

2. ⏳ Extend `pack/skills/engineer/SKILL.md`'s "Authoritative type signatures per step" subsection with an explicit "single source of truth" note: "The signatures block is the authoritative source. Other parts of the step entry (test list, conventions applied, why-this-order, SOLID notes) may *reference* the signatures but should not re-state them. Reduces plan length without losing information." Mirror.

**Forward-references for later slices** (no action now; tracked here):

- Slice 4: `/checkpoint` should explicitly support spec amendments triggered by `/plan` research findings (this dogfood did the amendment manually). The Prerequisites-section pattern this amendment used is a candidate for canonical handling.
- Slice 6: `/feature-merge` should support "supersede" as a transition for parked features the merging feature has absorbed.
- Install scripting: state.md template's mainline-branch assumption + bytecode-gitignore prerequisite should be called out.

## Skill content gaps surfaced but deferred

- **Two-architect-per-feature numbering.** Slice-2 produced ADR-0001 mid-feature; slice-3 produced ADR-0002 mid-feature. Numbering was sequential and trivially handled, but the pm skill's "next free number" instruction doesn't address what happens if two architect invocations happen concurrently (different threads or interrupted plans). Vanishingly unlikely at dogfood scale; defer until evidence forces it.
- **Plan re-runs.** `/plan` refuses if a plan file exists. The user deletes and re-runs to redraft. If the user instead wants to *amend* a draft plan (mid-authoring), there's no documented mechanism short of `/checkpoint` (slice 4). The current refuse-and-restart works for slice 3; slice 4 should consider whether `/plan --amend` is worth a separate path.
- **Pre-built plan template file.** Same risk as the spec template — encourages cargo-culting over thinking. Defer; revisit if plan output starts looking template-shaped instead of feature-shaped.
- **The Conventions table format.** I used a three-column "Convention / Evidence / Apply how" table for repo conventions and a three-column "Constraint / Source / Implication" table for framework constraints. Both formats work; consistency might help. Defer until a second plan-generation slice finds one or the other lacking.

## What was NOT validated

Honest list:

- **Plan approval transition.** User did not flip the plan from `draft` to `approved` in this dogfood. One-line user edit; pack doesn't need to do anything.
- **`/build` against this plan.** Plan is sitting at `status: draft`. Multi-step state.md handoff between Step 1 → Step 7 wasn't exercised (slice-1 dogfood didn't either; this is becoming a chronic gap). Should be exercised in slice-4 dogfood naturally — that's where `/checkpoint` interleaves with `/build`.
- **Plan re-run after spec amendment.** The spec was amended during `/plan`; `/plan` continued without re-running from the top. The command doesn't explicitly say what to do — re-run the orient phase (mostly redundant) or continue from research? In this dogfood I continued from research because the amendment was strictly additive (didn't invalidate prior orient findings). If a future amendment were more substantive, re-running from Phase A would be the right call. Worth a small `/plan` clarification.
- **`/plan` halt on a spec criterion that has no plausible step.** This dogfood's halt was on spec-internal-consistency; the criterion-without-step halt path was not exercised because the amendment resolved that risk too.
- **Architect declining to draft an ADR** (returning "follow precedent without ADR"). Both architect calls so far have produced ADRs.
- **Architect's "ask a clarifying question instead of guessing" branch.** Both calls had sufficient context.
- **PM skill's plan-time "stop and ask" branches.** None triggered; user answers and architect returns were consistent.
- **The acceptance-mapping table's deliberate-omission Note column.** No criteria were deliberately omitted in this plan.

These should be exercised in slice 4 or later dogfoods as natural cases surface.
