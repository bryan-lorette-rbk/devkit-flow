# ADR-0001: Compositional Skill-Pack Architecture for Claude Code

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** [user], Claude (design partner)

---

## Context

We need a Claude Code workflow system that enforces a specific engineering shape:

- Large features decomposed into clear domains
- Spec-first development with per-domain brainstorming
- Implementation plans derived from approved specs
- Branch-per-feature with merge-to-main on completion
- Non-negotiable practices: TDD, SOLID, Clean Architecture
- Living documentation — specs, plans, ADRs, summaries always current
- Small-team context (not enterprise ceremony)

Existing frameworks each get part of this right but miss something material:

- **BMAD / SpecKit** — strong spec rigor, but heavy phase count and verbose artifacts; build a parallel universe on top of the tool instead of using its primitives
- **GSD (Get-Shit-Done)** — good branch-per-feature loop and lighter weight, but thin on spec and domain decomposition
- **Obra Superpowers** — excellent TDD discipline and verification rigor, but loses whole-project scope; documentation is thin; optimizes the current task at the cost of project memory

The system must use **native Claude Code primitives** (subagents, skills, slash commands, hooks, CLAUDE.md) wherever possible rather than inventing parallel mechanisms.

## Decision

Build a fresh compositional skill-pack rather than extending Superpowers or paring back GSD. The pack composes:

- Superpowers' TDD and verification discipline (in the `engineer` skill and `tester` subagent)
- A thin spec/domain front-end inspired by SpecKit (in the `pm` skill and `/feature-start` command)
- GSD's branch-per-feature loop (in `/feature-start` and `/feature-merge`)
- Native Claude Code primitives as the substrate throughout

### Component breakdown

**Subagents (3) — isolated context is genuinely necessary:**

| Agent | Why isolated context |
|---|---|
| `architect` | Design thinking benefits from absence of implementation bias; produces ADRs |
| `tester` | TDD integrity requires writing tests without seeing the implementation |
| `security-reviewer` | Fresh-eyes pass before merge catches what the implementer normalized |

**Skills (3) — instructions the main thread follows; no isolation needed:**

| Skill | Role |
|---|---|
| `engineer` | TDD red-green-refactor loop; SOLID checklist; Clean Architecture layering rules; Karpathy-style small reversible steps with verify-as-you-go |
| `documenter` | Owns the doc-currency invariant; runs at phase transitions and `/checkpoint`; reconciles docs against repo state |
| `pm` | Feature decomposition, domain mapping, brainstorming patterns, spec drafting |

**Slash commands (5) — workflow phase entry points:**

| Command | Phase |
|---|---|
| `/feature-start <name>` | Brainstorm → domains → spec → branch creation |
| `/plan` | Approved spec → implementation plan + test list |
| `/build` | Execute plan under TDD |
| `/checkpoint` | Mid-feature doc-sync and state reconciliation |
| `/feature-merge` | Security review → final docs reconciliation → merge → archive |

**Hook (1) — `PostToolUse` doc-drift detector:**

Fires after Edit/Write on source files. Compares modified files against the active feature's spec/plan (from `.claude/state.md`) and surfaces drift as a warning Claude must address before continuing. Does not auto-edit docs — too risky. Surfacing drift is the job; resolving it is the documenter skill's job.

Start with simple heuristic (any edit under `src/` flags active feature docs as potentially stale). Refine with spec/plan front-matter declaring owned files once we have usage data.

### Memory layout (hybrid)

```
docs/                    # human-first, durable
  specs/<feature>.md     # source of truth: what we're building
  plans/<feature>.md     # source of truth: how we're building it
  adr/NNNN-<name>.md     # architecture decisions
  domains/<domain>.md    # living project domain model
  summaries/<feature>.md # generated retrospectives, callouts
.claude/                 # machine-first, working state
  state.md               # current branch, active spec, phase, open questions
  skills/                # the skill-pack
  agents/                # subagent definitions
  commands/              # slash command definitions
  hooks/                 # doc-drift detector
CLAUDE.md                # index pointing at state.md, domains/, active spec
```

Memory-palace analogue: `specs/`, `plans/`, `adr/`, `domains/` are the "rooms" — location-addressable, durable, navigable. `state.md` is the working-memory pointer that tells Claude which room is currently active.

### Doc-currency enforcement (defense in depth)

The "docs must stay current" requirement is the system's hardest invariant. Three layers, each fast-failing:

1. **Hook layer (automatic)** — `PostToolUse` detects code edits and surfaces drift warnings.
2. **Skill layer (workhorse)** — `documenter` skill invoked at every phase transition and `/checkpoint`; performs actual reconciliation.
3. **Command layer (gate)** — `/feature-merge` blocks if drift detected; no merge with stale docs.

No single layer is sufficient. The hook catches drift in real time but can't fix it. The skill can fix drift but only when invoked. The command gates merge but lets mid-feature drift accumulate. Layered together, they make stale docs structurally hard to ship.

## Rationale (mapped to requirements)

| Requirement | How the design satisfies it |
|---|---|
| Domain breakdown | `/feature-start` runs PM-led decomposition; output captured in spec and reflected in `docs/domains/` |
| Spec-first | `/feature-start` produces spec before any plan; `/plan` blocks without approved spec |
| Brainstorm-to-spec | PM skill owns the brainstorming pattern; architect subagent invoked for design questions during brainstorm |
| Implementation plan | `/plan` is a discrete phase producing `docs/plans/<feature>.md` with test list |
| Branch-per-feature | `/feature-start` creates branch; `/feature-merge` merges and archives |
| TDD enforced | `tester` subagent writes tests in fresh context; `engineer` skill enforces red-green-refactor |
| SOLID enforced | `engineer` skill includes SOLID checklist applied to every diff |
| Clean Architecture | `engineer` skill includes layering rules; `architect` subagent invoked when boundaries are ambiguous |
| Living docs | Three-layer enforcement (hook + documenter skill + merge gate) |
| Lean personas | 6 roles compressed into 3 agents + 3 skills based on context-isolation need |
| Native-first | Uses Claude Code subagents, skills, slash commands, hooks, CLAUDE.md — no parallel mechanisms |
| Karpathy-style | `engineer` skill encodes small reversible steps + think-out-loud + verify-as-you-go |
| Memory-palace | Hybrid memory layout provides location-addressable durable context |
| Small team | No PM-as-agent overhead; no enterprise ceremony; artifact set is intentionally bounded but not arbitrarily capped |

## Alternatives considered

**Extend Obra Superpowers.** Inherits the project-amnesia architecture; we'd be bolting the missing front-end onto a system whose shape doesn't accommodate it. Highest integration cost.

**Pare back GSD.** Starts from something already lighter than the target; we'd be adding back the discipline GSD intentionally omits. Better than extending Superpowers, but the result is constrained by GSD's shape rather than ours.

**Build fresh compositional pack.** Highest upfront cost, but the result fits the user's engineering shape rather than fighting someone else's. Selected.

## Consequences

**Positive:**
- Workflow matches the user's actual development shape
- Doc-currency is structurally enforced, not aspirational
- Native-primitive use means the pack benefits automatically from Claude Code improvements
- Small surface area (3 agents, 3 skills, 5 commands, 1 hook) keeps the system inspectable

**Negative / risks:**
- More upfront authoring work than paring back GSD
- Hook-based drift detection may produce false positives early; mitigated by simple-first heuristic and iteration
- Three doc-currency layers means three places to maintain; mitigated by each layer having a distinct, narrow job

**Open questions:**
- Exact heuristic for hook drift detection (will be refined in use)
- Whether `documenter` should ever become a subagent if doc reconciliation grows complex (deferred until we have evidence)
- Whether `pm` and `engineer` should be split further (deferred; collapse first, split if needed)

## Build order

Smallest useful slice first, so the pack is dogfood-able before it's complete:

1. `engineer` skill + `/build` command + `tester` subagent — minimum viable TDD loop
2. `/feature-start` + `pm` skill + `architect` subagent — spec/domain front-end
3. `/plan` command — bridge between spec and build
4. Memory layout + `documenter` skill + `/checkpoint` command — doc-currency workhorse
5. Drift-detection hook — doc-currency automation layer
6. `security-reviewer` subagent + `/feature-merge` command — closeout and gate

Each slice is independently usable. After slice 1, you have a working TDD assistant. After slice 3, you have full spec-to-build flow. After slice 5, docs are structurally protected. After slice 6, the full pack is in place.