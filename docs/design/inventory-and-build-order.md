# Skill Inventory & Build Order

**Purpose:** Name every component in the pack, describe what it reads/writes, and lay out a build order that makes the pack dogfood-able before it's complete.

---

## Inventory

### Subagents (3)

| Name | Trigger | Reads | Writes | Notes |
|---|---|---|---|---|
| `architect` | Invoked by PM skill during `/feature-start` brainstorm when design questions arise; by Engineer skill during `/build` when Clean Architecture boundary is ambiguous | Active spec, `docs/domains/`, `docs/adr/`, relevant source | Returns a recommendation + ADR draft to the calling context | Fresh context. Sees the question, not the implementation. Outputs are advisory; caller decides whether to accept |
| `tester` | Invoked by Engineer skill at the start of each `/build` step | Active spec, plan's test list for the current step, type signatures of code-under-test, **not** implementation source | Test files only | Fresh context is load-bearing here. Cannot see implementation while writing tests. This is the TDD integrity guarantee |
| `security-reviewer` | Invoked by `/feature-merge` as gate 3 | Diff of the feature branch vs main, active spec, `docs/adr/` | Review notes (structured findings + severity) to the calling context | Fresh context. No prior conversation about the implementation choices |

### Skills (3)

| Name | Trigger | Reads | Writes | Notes |
|---|---|---|---|---|
| `engineer` | Loaded by `/build`; also by `/plan` for planning-time discipline | Active plan, current step, existing source for context | Source files, test files (after tester returns), commits | Encodes TDD red-green-refactor loop, SOLID checklist, Clean Architecture layering rules, Karpathy-style small reversible steps. The pack's largest skill by content volume |
| `documenter` | Loaded by `/checkpoint`, `/feature-merge`; on-demand when hook surfaces drift | All of `docs/`, `.claude/state.md`, current diff | Spec amendments, plan amendments, ADRs, summaries, domain doc updates, state.md | Always proposes before writing. Never auto-edits docs without user confirmation. Owns the doc-currency invariant in practice |
| `pm` | Loaded by `/feature-start` for brainstorm + decomposition; by `/plan` for plan generation | `docs/domains/`, `docs/specs/` (for shape consistency), user input | Spec drafts, plan drafts, state.md updates | Owns the brainstorm-to-spec dialogue pattern and the domain-decomposition heuristic. Invokes architect when design questions surface |

### Slash commands (5)

| Name | Purpose | Preconditions | Postconditions |
|---|---|---|---|
| `/feature-start <name>` | Begin a feature: brainstorm → domains → spec → branch | No active feature in state.md; clean working tree | Branch created, spec drafted (status: draft), state.md updated; ADR if architect was invoked |
| `/plan` | Convert approved spec into implementation plan | Active feature; spec status = approved | Plan drafted (status: draft), state.md updated |
| `/build` | Execute the approved plan under TDD | Active feature; plan status = approved | One or more plan steps completed; source/tests committed; state.md updated per step |
| `/checkpoint` | Mid-feature doc-sync and spec/plan amendment | Active feature in any phase | Documenter has reconciled docs against repo state; user-requested amendments applied; state.md updated |
| `/feature-merge` | Close out the feature: tests + docs + security → merge → archive | Active feature; plan complete; tests green | Summary doc generated, domain docs updated if applicable, branch merged to main, branch archived, state.md cleared |

### Hook (1)

| Name | Type | Fires on | Behavior |
|---|---|---|---|
| `doc-drift-detector` | `PostToolUse` | Edit / Write on files under `src/` (configurable) | Reads active feature from `.claude/state.md`. Checks edited file path against active spec's `owned_files` front-matter. If file is not in scope, surfaces a warning: "Edit touched `<path>`, which isn't listed in `<active-spec>.owned_files`. Either expand the spec's scope (`/checkpoint`) or move this change to a different feature." Does not block. Does not auto-edit |

### Memory layout (recap from ADR-0001)

| Path | Purpose | Lifecycle |
|---|---|---|
| `docs/specs/<feature>.md` | Spec — source of truth for *what* | Created at `/feature-start`; amended via `/checkpoint`; final state at merge |
| `docs/plans/<feature>.md` | Plan — source of truth for *how* | Created at `/plan`; amended via `/checkpoint`; final state at merge |
| `docs/adr/NNNN-<name>.md` | Architecture decision records | Created when architect subagent is invoked and produces a decision; immutable once accepted |
| `docs/domains/<domain>.md` | Living domain model | Updated by documenter at `/feature-merge` when feature changes the domain |
| `docs/summaries/<feature>.md` | Feature retrospective + change story | Created at `/feature-merge`; immutable after |
| `.claude/state.md` | Working state pointer | Continuously updated; cleared at `/feature-merge` |
| `CLAUDE.md` | Index pointing at state.md, domains/, active spec | Stable; updated rarely (when memory layout itself changes) |

---

## Component dependency graph

What depends on what (for build ordering):

```
                  ┌─────────────┐
                  │ memory      │  (just the directory structure +
                  │ layout      │   CLAUDE.md index — no code)
                  └──────┬──────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
   ┌──────────┐   ┌──────────┐   ┌──────────────┐
   │ engineer │   │ pm skill │   │ documenter   │
   │ skill    │   │          │   │ skill        │
   └────┬─────┘   └────┬─────┘   └──────┬───────┘
        │              │                │
        ▼              ▼                │
   ┌──────────┐  ┌─────────────┐        │
   │ tester   │  │ architect   │        │
   │ subagent │  │ subagent    │        │
   └────┬─────┘  └─────┬───────┘        │
        │              │                │
        │              ▼                │
        │       ┌──────────────┐        │
        │       │ /feature-    │        │
        │       │ start        │        │
        │       └──────┬───────┘        │
        │              │                │
        │              ▼                │
        │       ┌──────────────┐        │
        │       │ /plan        │        │
        │       └──────┬───────┘        │
        │              │                │
        ▼              ▼                ▼
   ┌──────────────────────────────────────────┐
   │ /build           /checkpoint             │
   └────────────┬─────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │ security-     │
        │ reviewer      │
        └──────┬────────┘
               │
               ▼
        ┌───────────────┐
        │ /feature-     │
        │ merge         │
        └───────────────┘

        (orthogonal, can be added any time after /build exists)
        ┌──────────────────────┐
        │ doc-drift-detector   │
        │ hook                 │
        └──────────────────────┘
```

---

## Build order

Six slices. Each is independently usable on a real feature. Stop and dogfood after every slice — that's the whole point of the slicing.

### Slice 1 — Minimum viable TDD loop

**Build:**
- Memory layout (just the directories + a stub `CLAUDE.md` + an empty `state.md`)
- `engineer` skill (TDD loop, SOLID checklist, Clean Arch rules, Karpathy discipline)
- `tester` subagent definition
- `/build` command

**What you can do after this slice:**
Use a hand-written plan in `docs/plans/<feature>.md` and run `/build` against it. Get the TDD loop working end-to-end on real code. This validates the most novel engineering content (the engineer skill) before anything else is built around it.

**Dogfood task:** Pick a small real feature in an existing project. Hand-write a 5-line plan with a test list. Run `/build`. Verify: tester writes tests in fresh context; engineer skill enforces red-green-refactor; SOLID and Clean Arch rules surface where relevant.

**Why this is slice 1:** It's the smallest useful slice. Everything else is workflow scaffolding around this loop.

---

### Slice 2 — Spec/domain front-end

**Build:**
- `pm` skill (brainstorm pattern, domain decomposition, spec drafting)
- `architect` subagent definition
- `/feature-start` command

**What you can do after this slice:**
Begin features properly. Brainstorm → domains → spec → branch. Then hand off to `/build` using a plan you still write by hand.

**Dogfood task:** Start a new feature with `/feature-start`. Verify: PM dialogue is useful and not bureaucratic; architect gets invoked when warranted; spec produced is actually useful as a contract.

**Why slice 2:** Validates the spec-first front-end before you commit to automating the plan generation. If the PM skill's brainstorm pattern is wrong, you want to know now — before `/plan` is built on top of it.

---

### Slice 3 — Plan generation

**Build:**
- `/plan` command (extends `pm` and `engineer` skills with planning behaviors)

**What you can do after this slice:**
Full spec-to-build flow. `/feature-start` → review spec → `/plan` → review plan → `/build`. No docs maintenance yet; that's slice 4.

**Dogfood task:** Take a feature through `/feature-start` → `/plan` → `/build`. Verify: plan structure matches what you actually want to execute; test lists are useful; step ordering respects Clean Architecture layering.

**Why slice 3:** With slices 1 and 2 validated, this is mostly orchestration. If the plan output is wrong, the fix is in the PM/Engineer skills (already built), not in `/plan` itself.

---

### Slice 4 — Doc-currency workhorse

**Build:**
- `documenter` skill
- `/checkpoint` command

**What you can do after this slice:**
Mid-feature amendments. The pack now actively maintains doc currency at every transition, not just at merge.

**Dogfood task:** Mid-build, deliberately change scope. Run `/checkpoint`. Verify: documenter proposes amendments before writing; spec and plan stay coherent; state.md reflects the change.

**Why slice 4:** Doc currency is the system's hardest invariant. Build the workhorse before the automated guards. If the documenter skill is wrong, the hook in slice 5 amplifies the wrongness.

---

### Slice 5 — Drift detection automation

**Build:**
- `doc-drift-detector` hook
- Add `owned_files` front-matter convention to spec template
- Update `pm` skill to populate `owned_files` when drafting specs

**What you can do after this slice:**
Drift surfaces automatically. Edits outside spec scope produce warnings the user must address.

**Dogfood task:** Deliberately edit a file outside the active spec's scope. Verify: hook fires; warning is useful; resolution path (via `/checkpoint`) is smooth.

**Why slice 5:** Layer on top of slice 4. Hook without documenter is a warning system with no fix path. Documenter without hook works but relies on user remembering to checkpoint. Combined, they make stale docs structurally hard.

---

### Slice 6 — Closeout and gate

**Build:**
- `security-reviewer` subagent definition
- `/feature-merge` command (with three gates: tests, docs, security)

**What you can do after this slice:**
Full feature lifecycle from start to merge. The pack is complete.

**Dogfood task:** Take a feature through the complete lifecycle. Verify: all three gates fire in order; security review surfaces useful findings; summary doc is genuinely retrospective, not boilerplate; domain docs update where appropriate.

**Why slice 6 last:** Merge gating only makes sense once everything it's gating on exists. Building this before slice 4 would be premature — you'd be gating on doc reconciliation that has nowhere to run.

---

## Build order rationale

A different order was tempting: **start with `/feature-start`** because it's where the user enters the workflow. Rejected for two reasons:

1. **The engineer skill is the most content-dense and least obviously right.** TDD discipline, SOLID, Clean Architecture, Karpathy-style — these are opinionated and need real validation. Get them wrong and everything downstream is built on sand. Putting this in slice 1 means it gets validated against real code earliest.

2. **`/build` is usable with a hand-written plan.** `/feature-start` is *not* usable without something to feed into. So slice 1 = `/build` produces a working tool from day one; slice 1 = `/feature-start` produces a tool that just sits there until slice 3.

The general principle: **build innermost first, then expand outward.** Engineer skill is the core; everything else is scaffolding that brings work to it.

---

## What "done" looks like

After all six slices:

- A feature can be started, scoped, planned, built, amended, reviewed, and merged through five commands
- Three subagents enforce isolation where it matters (TDD integrity, design objectivity, security fresh-eyes)
- Three skills carry the engineering, PM, and doc-currency discipline
- One hook makes drift visible in real time
- Five durable artifact types (spec, plan, ADR, summary, domain doc) carry project memory
- `.claude/state.md` is the working pointer that ties everything together
- The pack uses Claude Code native primitives throughout — no parallel framework

---

## Next concrete step

Pick a real project for the dogfood. Don't start writing skill content yet — start by defining what feature you'll run through slice 1 once it exists. The skill content will be much sharper if it's authored against a concrete validation case rather than in the abstract.

Suggested format for that pick:

```
Dogfood project: <name>
Slice 1 validation feature: <small real feature, ideally one you've been
putting off because it's boring>
Why this feature: <small enough to fit, real enough to surface problems>
```

Once that's locked, slice 1 authoring begins.