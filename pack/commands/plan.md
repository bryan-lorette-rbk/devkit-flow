---
description: Convert an approved spec into a typical-depth implementation plan with research-grounded conventions, per-step type signatures, and acceptance-criteria mapping. Loads the `pm` skill (plan-time behaviors — research, acceptance mapping) and the `engineer` skill (plan-time behaviors — step ordering, step shape, tester contract). Invokes the `architect` subagent when research surfaces a first-of-kind cross-cutting decision. Pauses for user review and approval; does not flip status itself.
---

Drive the `pm` and `engineer` skills from an approved spec to an approvable draft plan. One `/plan` invocation produces one draft plan; the user reviews and approves before `/build` runs.

## Arguments

`/plan` takes no arguments. It operates on the active feature named in `.claude/state.md`. If the user wants to plan a different feature, they switch state first (or use `/feature-start` for a new one).

## Preconditions

Before doing anything visible to the user:

1. Read `.claude/state.md`.
2. Verify all of the following — if any is false, **stop and report what is missing** (do not work around it):
   - `Active feature` is not `none`.
   - `Spec` points to an existing file.
   - The spec's front-matter contains `status: approved`. If the spec is `draft`, surface that and stop — the user reviews and approves the spec first.
   - `Plan` is `—` (no plan exists yet) **or** the plan file does not exist on disk. If a plan file exists already, surface that and stop — the user either deletes the existing draft (to re-plan from scratch) or uses `/checkpoint` to amend it (slice 4; for now, manual edits).
3. Working tree may have uncommitted changes; `/plan` writes a new file and does not change branches.

If preconditions pass, continue. State.md's `Phase` may be `spec-approved` (clean handoff from `/feature-start`) or something else (e.g., user manually transitioned); don't gate on Phase, gate on the spec's own `status` and the plan-not-yet-existing condition.

## Run

Load the `pm` skill (for plan-time behaviors: research, acceptance mapping, cross-cutting pattern check) and the `engineer` skill (for plan-time behaviors: step ordering, step shape, tester contract). Both skills' "Plan-time behaviors" sections are the source of truth for the discipline; this command sequences the phases and handles side-effects (file writes, state.md updates, ADR persistence).

### Phase A — Orient

Read, in this order:
- `CLAUDE.md` (project conventions).
- The active spec (path from state.md).
- `docs/specs/` for one or two recent merged specs — gives shape context.
- `docs/plans/` for any merged plans on adjacent features — these are the best evidence of what a typical plan in *this* project looks like.
- `docs/domains/<domain>.md` for each domain the spec touches.
- `docs/adr/` titles; read in full any ADR named in the spec's `related_adrs` front-matter or any whose title is keyword-relevant to the feature.

If the spec's `owned_files` glob excludes a directory you'd expect the feature to touch, surface that as a likely spec gap — flag, don't silently widen scope.

### Phase B — Research (REQUIRED)

Per the pm skill's "Research phase (required, not optional)" section, produce three buckets of grounded evidence:

- **Repo conventions** — observed precedents with file:line citations. Read multiple existing modules in the affected directories; do not generalize from one file.
- **Project-firsts** — patterns this feature introduces for the first time, each justified with explicit reasoning. *These are the cross-cutting-pattern candidates.*
- **Framework constraints** — researched from framework internals (or current docs) where behavior matters. Cite the source.

This phase is the difference between a plan that drives correct code and one that drives stylistically detached code that has to be re-styled later. Do not shortcut it. If a relevant repo file doesn't exist yet (the feature is establishing a new directory), say so — that's evidence the area is a project-first, not a reason to skip research.

### Phase C — Cross-cutting pattern check

After research, audit the project-firsts you identified in Phase B against the pm skill's "When to invoke the architect" criteria (specifically the cross-cutting-pattern subsection — framework-exception translation, retry policy, transaction boundary, logging shape, validation cascade, authorization placement, pagination convention, and similar).

For each first-of-kind cross-cutting decision found, **invoke the `architect` subagent in fresh context** before drafting it into the plan. See "Invoking the architect" below for the invocation mechanic. Surface the architect's recommendation to the user; do not silently apply.

If the architect drafts an ADR, write it under `docs/adr/NNNN-<short-name>.md` with the next free number and reference it in the plan's front-matter `related_adrs`.

This is the slice-2 forward-reference: the pm skill almost missed a cross-cutting pattern at spec time; the same risk applies even more sharply at plan time when decisions get baked into multiple steps.

### Phase D — Step decomposition

Per the engineer skill's "Step ordering" and "Each step's required entries" sections, decompose the feature into steps. Each step must:

- End in a green test suite.
- Be independently revertable.
- Have Files (new/modified), authoritative type signatures for the tester, a test list, conventions-applied bullets, a one-line why-this-order, and SOLID/Clean Arch notes where relevant.
- Be flagged with a smoke-import note if the engineer skill's "Smoke-import prediction" criteria apply.

If the analysis predicts a Step 1 that can't reach red because of a prerequisite (broken legacy import in a chained `__init__.py`, missing package initializer, etc.), include a **Step 0 prerequisite** in the plan that fixes it before Step 1 runs. Don't ship a plan whose Step 1 fails the smoke-import check.

### Phase E — Acceptance mapping

Per the pm skill's "Acceptance mapping" section, enumerate every acceptance criterion from the spec into a checklist table. Map each criterion to the step(s) that satisfy it, or mark it as a deliberate omission with a one-line reason. No criterion may map to "—" without a reason.

If the mapping reveals a criterion that has no plausible step (because the spec is internally inconsistent, or the criterion implies a behavior the plan doesn't account for), surface it — the spec may need amendment.

### Phase F — Write plan + update state.md

Write `docs/plans/<slug>.md` with:

```yaml
---
feature: <slug>
status: draft
spec: docs/specs/<slug>.md
related_adrs: [<numbers including any drafted in Phase C>]
---
```

Sections in order:

1. **Approach** — TDD throughout; dependency order rationale; test runner / linter / typecheck identification (concrete commands like `uv run pytest`, not abstract "we use pytest").
2. **Conventions and constraints** — three subsections from Phase B (Repo conventions, Project-firsts, Framework constraints), each with its evidence table.
3. **Step order** — each step entry per the engineer skill's "Each step's required entries" list.
4. **Acceptance mapping** — the table from Phase E.
5. **Out-of-plan changes that may surface** — lint-rule additions, one-time migrations, anything you anticipate needing that's outside the spec's strict scope. Surface here; don't surprise the user during `/build`.

If `docs/plans/` doesn't exist, create it.

Update `.claude/state.md`:
- `Phase: plan-draft`
- `Plan: docs/plans/<slug>.md`
- `Next step: Step 1 — <step name>` (the heading of the first step, so `/build` has something to point at the moment the user approves the plan)

Leave `## Open questions` alone unless the research or architect invocation surfaced something to defer.

### Phase G — Commit and hand off

Before the pause, propose a single commit for the artifacts this invocation produced: the plan, any Phase-C ADRs, the Phase-F `.claude/state.md` updates, and any spec front-matter `related_adrs` amendment Phase C made. Subject: `plan: <slug> (draft, <N> steps)`. Body: one short paragraph — the plan's approach in one sentence, ADR numbers if any. Stage these files explicitly; never `git add -A` (same reasoning as the engineer skill's commit substep). Wait for confirmation; on decline, leave the proposal visible and proceed to the pause without committing. If Phase C produced architect-driven ADRs, the user may prefer per-ADR commits — surface that option in the decline branch.

Then pause for the user. Surface, in one short message:

- The plan path.
- Any ADRs written in Phase C.
- The commit status (committed / proposal-declined / nothing-to-commit-yet).
- A one-line prompt: "Review the plan; when ready, change its front-matter `status` from `draft` to `approved`, commit that change, and run `/build`."

Do not auto-approve the plan. The approval-status flip is the user's separate commit between `/plan` and `/build` — the precedent message is `approve plan: <slug>`. `/build` reads the plan's front-matter `status` directly, so the user only needs to edit the plan file — state.md's `Phase` is descriptive.

## Invoking the architect

When Phase C identifies a first-of-kind cross-cutting decision, invoke the `architect` subagent via the `Agent` tool. Use `subagent_type: architect` if the host project's pack install resolves it; otherwise fall back to `subagent_type: general-purpose` with the contents of `.claude/agents/architect.md` (or `pack/agents/architect.md` in the dev tree) pasted at the top of the prompt body. Either way the architect runs in fresh context, which is the integrity guarantee.

Pass the architect:

- The question framed in one sentence.
- The trade-offs you've already considered.
- Paths to: the active spec, the in-progress plan draft (if any sections are written), relevant `docs/domains/<domain>.md` files, relevant `docs/adr/NNNN-*.md` files.
- Pointers to source files the architect should sample.

The architect returns a recommendation, rationale, trade-offs, precedent, and (if warranted) an ADR draft. Reflect the recommendation back to the user before accepting; the user's confirmation is the gate before applying it to the plan or writing an ADR.

## Halt conditions

Stop and surface to the user (do not auto-recover) if:

- Preconditions fail (no active feature, spec not approved, plan already exists).
- Research surfaces evidence that the spec is internally inconsistent or names files/conventions that don't exist (suggests the spec needs amendment before `/plan` can proceed).
- The architect returns a recommendation that conflicts with what the spec commits to (the spec may need amendment via `/checkpoint`).
- Acceptance mapping leaves a spec criterion unable to map to any step or deliberate-omission (suggests the spec criterion is unimplementable as stated).
- The user rejects an architect recommendation but has no alternative direction — surface the disagreement, don't proceed with either option.
- The proposed commit cannot be staged (e.g., a file Phase C/F expected isn't on disk, or `git add` errors out). Surface; do not work around it.

Plan generation is not a one-shot script; if any of these conditions surface, halting and asking is cheaper than producing a plan that has to be redone.
