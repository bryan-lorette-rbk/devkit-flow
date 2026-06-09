# Slice 2 — Dogfood Validation Report

**Slice:** 2 (spec/domain front-end — `pm` skill, `architect` subagent, `/feature-start` command)
**Dogfood target:** chungar (`/Users/bryanlorette/Code/rubrik-chungarsih-agent`)
**Validation feature:** `write_note` + `delete_note` tools (paired with the existing notes domain)
**Status:** complete with one pre-slice-3 revision recommended
**Date:** 2026-06-01

## Executive summary

Slice 2's pack content (pm skill, architect subagent, `/feature-start` command) drove a real interactive brainstorm to an approvable-shape draft spec, plus an ADR after a post-brainstorm architect invocation surfaced a cross-cutting pattern decision the pm skill missed in-flight. The spec landed at ~270 lines and matches typical-depth — all twelve sections from the authoring-note checklist present, with cuts visible where they happened.

The simulation also exercised:

- **`/feature-start`'s precondition gate** (correctly halted on chungar's parked notes-read-and-search active state — a useful real-world friction moment, see Finding 1).
- **The architect fallback invocation pattern** (Agent tool with `subagent_type: general-purpose` and the architect role definition pasted into the prompt body — works, see Finding 4).
- **The pm skill's extend-by-default heuristic** (correctly resolved "extend the existing notes domain" without burning a fresh-context architect call — see Finding 3).
- **The pm skill's "when to invoke architect" criteria** (the in-flight brainstorm under-applied them on cross-cutting patterns — see Finding 2).

One pre-slice-3 revision is recommended: tighten the pm skill's "when to invoke architect" criteria for cross-cutting-pattern decisions specifically, with a worked example. The slice-2 artifacts are otherwise shippable.

## Findings

### Finding 1 — Precondition gate works; install-state friction is real

**Surface:** First action of `/feature-start` was to read chungar's `.claude/state.md`. It correctly halted because `notes-read-and-search` was still mid-build (Phase: building, Step 2 next). The user resolved by parking the prior feature (reset state.md to idle on master, leaving the feature branch intact for later resumption).

**What worked:** the halt was immediate, the failure mode was reported clearly, and the resolution path was obvious. The precondition check is doing its job.

**Real friction surfaced:** chungar's master branch state.md said `Active branch: main` — wrong for chungar (mainline is `master`). Small content nit in the pack install, but it's evidence that the state.md template assumes `main` and doesn't accommodate `master`-default repos. Worth either (a) detecting the project's default-branch at install time, or (b) saying "main (or your project's mainline)" in the template. Defer to whenever install scripting lands.

**Real friction surfaced #2:** there's no graceful way to "park" an in-progress feature today. Slice-1 deferred its 5-step feature after step 1, but the dogfood pack has no documented escape valve — the user had to manually reset state.md and add a "Parked features" note. `/checkpoint` (slice 4) and `/feature-merge` (slice 6) both assume a feature *concludes*; the parking case is unhandled. Worth a small addition to either the pm skill's onboarding or the slice-4 `/checkpoint` content — explicitly allow "park this feature, return to idle" as a transition.

**Recommended changes:**

- Pre-slice-3: add a "Parked features" section template to `pack/state.md.template` with a one-line note about how to park. Cost: ~10 lines.
- Slice 4: when `/checkpoint` ships, it should support `park` as a valid transition out (clears Active feature + Phase without merging, records the branch under Parked features).

### Finding 2 — pm skill missed an architect invocation on a cross-cutting pattern

**Surface:** During the brainstorm I (PM, in this conversation) made an implicit decision in the draft spec: `NoteWriteService.create()` catches `pydantic.ValidationError` and translates to a domain-level `Invalid` result. That's a textbook cross-cutting pattern decision — every future write service in chungar will face the same choice — and the pm skill's own criteria say "invoke the architect for cross-cutting pattern decisions." But the in-flight brainstorm did not surface it as architect-worthy; the decision went into the spec as if it were a routine implementation detail.

The miss was caught only because I re-read my own draft and noticed the "Risks / known trade-offs" entry naming it as a coupling-with-Pydantic trade-off. That trade-off framing was itself the signal that the decision deserved an architect's eyes.

**Root cause:** the pm skill's "when to invoke architect" criteria list "cross-cutting pattern" as a trigger, but doesn't give an example of *what makes something cross-cutting in a way that's easy to miss*. The cross-cutting nature of "service-level framework-exception translation" is invisible the first time you encounter it (it looks like a one-off implementation detail) and only becomes obvious the second or third time. By then it's already de-facto-decided.

**Impact:** In a real run, the PM would draft the spec, the user would approve it without flagging the implicit pattern decision, the implementer would build to spec, and the pattern would be baked into the codebase before the architect ever got a look. That's exactly the failure mode "invoke for cross-cutting patterns" exists to prevent.

In this simulation, the post-hoc architect invocation worked (Finding 4) — but a "post-hoc architect invocation" is friction; the pattern is supposed to catch it in-flight.

**Recommended changes (pre-slice-3):**

- Add to the pm skill's "When to invoke the architect" section a worked-example bullet specifically for cross-cutting *patterns*: framework-exception translation, retry policy, transaction boundary, logging shape, validation cascade. Each looks one-off the first time and becomes load-bearing the second time. When a spec section's "Risks / known trade-offs" or "Integration / wiring" entry names a pattern decision in passing, that's a cue to step back and invoke the architect.
- Also add: when the pm skill writes a "this is a new project-first" entry under Conventions in a plan (slice 3), the same cue applies. (Forward-reference for slice 3.)
- Consider amending the pm skill's brainstorm loop to include an explicit "before drafting, list any cross-cutting patterns this feature establishes" checklist step. Cheap insurance.

This is the slice-2-specific equivalent of slice-1's Finding 1 (the walkthrough's spec template was too thin): the pm skill *almost* gets this right but leaves a load-bearing edge case under-specified.

### Finding 3 — Extend-by-default heuristic correctly resolved the domain question

**Surface:** The brainstorm's domain-decomposition step proposed "extend the existing notes domain" for write/delete without invoking the architect. The pm skill's heuristic ("default to extension; introduce a new domain only with specific evidence the existing one doesn't fit") applied cleanly: write/delete obviously belongs in `notes`, the data shape is unchanged, no new vocabulary emerges. No architect call needed; ~30 seconds of decision time instead of a fresh-context detour.

**Positive validation signal.** This is exactly the cost-savings the heuristic was designed to produce. Fresh-context invocations are not free (tokens and user time); avoiding one on a question that doesn't need it preserves the architect's invocation budget for the genuinely-architectural ones.

**No change recommended.** This is working as designed.

### Finding 4 — Architect fallback invocation pattern works end-to-end

**Surface:** When I did invoke the architect post-brainstorm (per Finding 2), I used the documented fallback pattern: `Agent` tool with `subagent_type: general-purpose` and the entire content of `pack/agents/architect.md` (the role definition) pasted at the top of the prompt body, followed by the question and context pointers.

The architect returned a substantive, on-spec response:
- Correctly identified that the read/search "precedent" the PM was reasoning from was weaker than it looked (no exception path involved).
- Identified an actual spec gap (the `ValidationError → InvalidField` mapping was unspecified) and flagged it without silently filling it in.
- Drafted a complete ADR matching the prescribed shape from the role definition.
- Used the `Read` tool to actually read the spec, prior spec, and CLAUDE.md before answering — confirming the role definition's "read first, cite always" guidance was followed.
- Stayed in scope (didn't propose refactors, didn't write production code).

**Positive validation signal.** The fallback pattern is operationally viable until the pack's subagent installation format stabilizes. The cost is one extra ~30-second context-loading round for the role definition, paid once per invocation. Worth it.

**Caveat worth recording:** the role definition got included in the prompt at ~3kB. That cost is paid every architect invocation. If invocations become frequent, the eventual native-subagent install path (where the role lives in `.claude/agents/` and the harness loads it automatically) will become a meaningful efficiency win. Until then, fallback is fine.

**No change recommended for slice 2.** The pattern is documented in `pack/commands/feature-start.md` under "Invoking the architect" as a "slice-2 simulation note." That note can be deleted whenever native subagent install lands.

### Finding 5 — Spec hit typical-depth on first draft

**Surface:** The draft spec for notes-write-and-delete came in at ~270 lines covering all twelve sections from `docs/authoring-notes/spec-and-plan-depth.md`. No section was silently dropped; the few that didn't apply (e.g., no schema changes — so no migration section) were either folded into an existing section with a one-line reason or noted explicitly in scope.

The pm skill's "default to typical depth" instruction (the slice-1 finding's remediation) worked. The first draft was usable as a contract without "beef this up" iteration. Compare to slice-1's first spec draft, which came in at ~70 lines and required a second pass.

**Positive validation signal.** The slice-1 → slice-2 corrective (encode typical depth in the pm skill, reference the authoring note) carried through to a real first-draft outcome. The authoring note + the pm skill's section checklist together are sufficient.

**One nit:** the spec's "Domains touched" section talks about decomposition in a way that overlaps slightly with "Clean Architecture layout" later. Not a problem here, but worth watching — if it becomes redundant in future specs, the pm skill might want to fold the two together with a layered description.

### Finding 6 — Brainstorm via AskUserQuestion batches felt right

**Surface:** I ran the brainstorm by batching questions into AskUserQuestion calls of 2–4 each (per the pm skill's "batch related questions" guidance). Six discrete questions across three batches resolved the entire spec contract:
- Batch 1 (4 questions): framing confirmation + write semantics + ID generation + delete shape.
- Batch 2 (3 questions): concurrency + delete kind + test-seeding refactor.
- Batch 3 (2 questions): clock injection + validation result shape.

Total interactive time was significantly less than a free-form back-and-forth would have been. The user could compare options side by side (the AskUserQuestion UI shows description + label per option), which surfaced trade-offs without the PM having to enumerate them in prose.

**Positive signal.** The "batch related questions" pattern in the pm skill is well-matched to AskUserQuestion's affordances. Worth keeping; if future evolution adds a multi-select pattern (e.g., "which of these sections to include"), the skill could call it out explicitly.

**Watch-out:** AskUserQuestion's option count is capped at 4. A few brainstorm questions had 4 options because I included a "you'll tell me" escape; if a question has 4 genuinely distinct viable answers plus an escape, it has to be split. Not a problem in this dogfood; worth noting.

## Validation feature progress

- [x] Slice-2 pack content authored (architect, pm, /feature-start) in `pack/`
- [x] Mirrored into `chungar/.claude/`
- [x] Pack-install commit on chungar's master branch
- [x] `/feature-start` precondition gate fired (parked notes-read-and-search resolved)
- [x] PM skill orient phase: read CLAUDE.md, docs/specs/, docs/domains/, docs/adr/ titles
- [x] Brainstorm: 3 AskUserQuestion batches, 9 questions answered, spec contract resolved
- [x] Domain decomposition: extension confirmed (no architect needed in-flight)
- [x] Spec drafted to typical depth (`docs/specs/notes-write-and-delete.md`, ~270 lines, all 12 sections)
- [x] Feature branch `feature/notes-write-and-delete` created on chungar
- [x] state.md updated to `Phase: spec-draft`
- [x] Spec committed
- [x] Architect invoked post-brainstorm via fallback Agent-tool pattern; returned recommendation + ADR draft
- [x] ADR-0001 written, spec amended with related_adrs + mapping subsection, committed

## Verdict

**Slice 2 passes with one pre-slice-3 revision recommended.**

Rationale:

- **Pack content drove a real spec from a real brainstorm.** The pm skill's brainstorm pattern, domain-decomposition heuristic, and typical-depth default all worked on a feature that wasn't designed-for. The `/feature-start` command's preconditions, branch creation, and state.md update fired correctly. The architect subagent (via fallback Agent-tool invocation) returned an on-spec response with all expected sections.
- **Finding 2 is the one real gap.** The pm skill's "invoke architect for cross-cutting patterns" criterion is too abstract — it correctly named the trigger but didn't give the kind of pattern-shaped example that makes the trigger easy to recognize in-flight. Fix is a small addition to the pm skill before slice 3 ships, since slice 3's `/plan` command will inherit the same risk on its "research and conventions" phase.
- **Findings 1, 3, 4, 5, 6 are positive signals or minor friction worth noting** but don't block slice 2 or require pack changes.
- **The simulation did not exercise** approval transition (user flipping spec status from draft to approved) or any downstream phase. Those are slice-3 dogfood concerns (the `/plan` command consumes the approved spec).

## Required pack revisions before slice 3

**Mandatory:**

1. ⏳ Extend `pack/skills/pm/SKILL.md`'s "When to invoke the architect" section with a worked-example bullet for cross-cutting *patterns* (framework-exception translation, retry policy, transaction boundary, logging shape, validation cascade). Add the "before drafting, list any cross-cutting patterns this feature establishes" pre-draft checklist step. Mirror into chungar's `.claude/skills/pm/SKILL.md`.

**Recommended (small):**

2. ⏳ Add a "Parked features" section template to `pack/state.md.template` with a one-line note on how to park (manually reset Active feature to none, append branch to the section). The slice-1 → slice-2 transition would have been smoother with this. Mirror.

**Forward-references for later slices (no action now):**

- Slice 3: `/plan` command should explicitly invite an architect invocation on cross-cutting decisions the conventions/research phase surfaces.
- Slice 4: `/checkpoint` should support `park` as an explicit transition out (clears Active feature without merging).
- Whenever install scripting lands: state.md template should detect the project's default branch instead of assuming `main`.

## Skill content gaps surfaced but deferred

- **Spec front-matter `owned_files` format.** Specs declare globs (`chungar/notes/**`), which slice-5's hook will use. The current pm skill says "be honest" about glob breadth but doesn't give a formal style (one glob per top-level scope area? combine? wildcard depth?). Worth a small section in the pm skill or in `docs/authoring-notes/`. Defer until slice 5 has concrete usage data.
- **ADR numbering when multiple are drafted in one feature.** This dogfood produced one ADR. If a future feature triggers two or three architect invocations, the pm skill should describe how to number them (sequentially during the feature, then re-number at write-time if collisions surfaced concurrently). Defer until a real two-ADR feature surfaces.
- **Pre-built spec template file.** Slice-2 specs are written from scratch following the checklist. A template file (`pack/templates/spec.md.template`) could lower friction — copy, fill in, run. Risk: a template encourages cargo-culting instead of thinking through sections. Defer; revisit if pm skill output starts looking template-shaped instead of feature-shaped.

## What was NOT validated

Honest list:

- **Approval transition.** The user did not flip the spec from `draft` to `approved` in this dogfood. That's a one-line edit, but the pm skill should articulate it more visibly (maybe in the hand-off message).
- **Multi-architect-per-feature flow.** Only one architect invocation occurred; two or three in sequence wasn't exercised.
- **Architect invocation during `/build`** (engineer skill's escalation to architect on ambiguous layering) — that's a slice-1 / slice-3 concern, not slice 2.
- **The `architect` subagent's "ask a clarifying question instead of guessing" branch.** The question was sufficiently scoped that the architect didn't need to clarify. Worth exercising in a future invocation.
- **The `architect` subagent's "don't duplicate prior ADRs" check.** Vacuously satisfied (no prior ADRs). Will become live the second time the architect is invoked.
- **Architect declining to draft an ADR.** The dogfood case warranted an ADR; the "no ADR needed, just follow precedent" return shape wasn't exercised.
- **PM skill's "stop and ask" branch** for genuinely conflicting answers from the user. Not exercised; user answers were internally consistent throughout.

These should be exercised in slice 3 or later dogfoods.
