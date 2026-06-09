# Authoring Note: Spec and Plan Depth

**Status:** active
**Created:** 2026-05-29 (after slice 1 dogfood)
**Related findings:** `docs/validation/slice-1.md` Findings 1 + 2

## Why this note exists

During slice 1 dogfood (authoring spec + plan for chungar's `notes-read-and-search`), the first drafts of both artifacts came in matching the *shape* of the examples in `docs/design/walkthrough.md` — and both were too thin. The walkthrough's examples demonstrate that specs and plans exist; they do not demonstrate the *depth* a typical real feature needs.

The fix: distinguish **minimum-viable** specs/plans (what the walkthrough showed pre-revision) from **typical** ones (what real features actually need). Author typical by default. The walkthrough examples have since been updated to model the typical shape.

## The rule

When drafting specs or plans for a real feature, default to **typical** depth. Use the section checklists below. Hold a section back only with an explicit reason ("No persistence — no schema section needed") rather than silently omitting it. Visible cuts beat invisible ones.

This applies to authoring artifacts in real projects using the pack, and to authoring the `pm`/`engineer` skills and `/plan` command — those skills must encode the typical templates, not the minimum-viable ones.

## Spec section checklist (typical)

Substantive specs include the following sections. Each can be cut for a specific feature *with a one-line reason in the spec body*.

- **Problem** — what need does this feature address; what changes for the user
- **Scope** — In / Out, both explicit
- **Domains touched** — new vs existing; expected folder layout
- **Data model** — entities, fields, types, constraints; storage schema if persisted
- **Tool / API / user-flow contract** — what the caller (LLM, HTTP client, end user) sees, including success and failure shapes
- **Error handling** — table per case: where the error surfaces and what happens; degenerate inputs called out
- **Clean Architecture layout** — file-by-file with dependency direction stated
- **Integration / wiring** — how layers compose at runtime, where config flows in, how the feature plugs into existing entry points
- **Testing strategy** — per layer: real values vs fakes vs mocks; what each layer exercises
- **Risks / known trade-offs** — concurrency, perf at scale, temporary couplings, deferred follow-ups
- **Acceptance criteria** — checkable, covering edge cases the spec describes
- **Open questions** — anything not yet decided

## Plan section checklist (typical)

Substantive plans include:

- **Approach** — TDD throughout; dependency order; test runner / linter / typecheck identification
- **Conventions and constraints** (the load-bearing section the walkthrough originally lacked)
  - **Repo conventions** — observed from existing files, with the *evidence* (file + line) cited
  - **Project-firsts** — patterns this slice introduces for the first time, with the chosen approach justified
  - **Framework constraints** — researched from framework internals where behavior matters
- **Step order** — each step has:
  - Files (new) and (modified)
  - Type signatures to give the tester (authoritative — the tester won't infer from elsewhere)
  - Test list
  - **Conventions applied** — which specific repo/framework pattern this step follows
  - Why this order
  - SOLID / Clean Arch notes
- **Acceptance mapping** — spec criteria → plan step(s) that satisfy them
- **Out-of-plan changes that may surface** — anything you anticipate needing that's outside the spec's strict scope

## Exemplars

**Walkthrough demonstrations** (updated 2026-05-29 to model typical depth):

- Spec: `docs/design/walkthrough.md`, Phase 1 — Goodreads import
- Plan: `docs/design/walkthrough.md`, Phase 2 — Goodreads import

**Real artifacts from slice 1 dogfood** (live examples, longer than walkthrough demos):

- Spec: `/Users/bryanlorette/Code/rubrik-chungarsih-agent/docs/specs/notes-read-and-search.md`
- Plan: `/Users/bryanlorette/Code/rubrik-chungarsih-agent/docs/plans/notes-read-and-search.md`

The walkthrough versions are tighter (illustrative). The chungar versions are full real artifacts. Reach for the chungar ones when you want to see "what does this actually look like in practice."

## When to break the rule

Minimum-viable specs/plans are appropriate when:

- The feature is a literal one-line code change (typo fix, single-line bug fix).
- The feature is a refactor with no user-visible behavior change AND the refactor is contained to one module.
- The "feature" is really just doc updates.

In all other cases — including refactors that span modules, bug fixes that cross layer boundaries, and any new functionality — default to typical depth.

## Pointer for slice 2 and slice 3 authoring

When the `pm` skill is authored in slice 2, encode the spec checklist above as the default the skill produces. When `/plan` is authored in slice 3, encode the plan checklist — including the research phase for the Conventions and Constraints section — as a required (not optional) step of plan generation.
