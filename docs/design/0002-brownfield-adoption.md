# ADR-0002: Brownfield Adoption — the `/adopt` pass

**Status:** Proposed
**Date:** 2026-06-22
**Deciders:** [user], Claude (design partner)

---

## Context

The pack installs cleanly into a project but only sets up *machinery*. `install.sh` creates `.claude/{skills,agents,commands,hooks,references}`, drops in the pack, installs `devkit-orientation.md`, seeds `state.md` to `idle`, and handles `CLAUDE.md` (stamp the slim template, or append/merge the orientation reference). It deliberately does **not** create `docs/` and it leaves `CLAUDE.md`'s `## Project conventions` as a literal `{{LIST_PROJECT_CONVENTIONS_HERE}}` placeholder.

That is correct for a greenfield project: the durable memory (`docs/domains/`, `docs/adr/`, `docs/specs/`, `docs/summaries/`) is grown organically, one feature at a time, exactly as slices 1–6 designed it.

It is **wrong for a mature project adopting the pack.** Every primitive's orient phase assumes that memory already exists:

- **pm / `/feature-start` orient** (`pack/skills/pm/SKILL.md` §1) reads `docs/domains/` "to understand the project's existing vocabulary and bounded contexts," skims prior `docs/specs/`, and reads `docs/adr/` titles.
- **`/plan` research phase** (same skill, "The research phase") cites repo conventions with `file:line` evidence.
- **architect** checks a recommendation against existing ADRs to detect contradiction.

On a long-lived project the day after install, all of that reads empty. The consequences compound:

1. The first `/feature-start` decomposition has no existing domain vocabulary to *extend* — its core heuristic ("default to extension") has nothing to extend against, so every slice of work looks like a new domain.
2. `CLAUDE.md` conventions are a placeholder, so the plan-time research phase re-derives import style / test idiom / DI pattern **from scratch on every feature**, and nothing durable is ever captured.
3. The architect has no ADRs to check, so it cannot detect "this contradicts a prior decision."

`/claude-md-merge` is the nearest existing primitive, but it only reconciles `CLAUDE.md` *structure* — it does not populate conventions from the actual code, and it touches nothing under `docs/`.

The gap was never designed for. The build-order doc's slices 1–6 all assume features are added to a project whose memory you grow from zero. There is no brownfield-adoption path.

## Decision

Add **one housekeeping slash command — `/adopt`** — that bootstraps the durable memory of an existing codebase to "a solid base" before the feature lifecycle runs. It mirrors `/claude-md-merge`'s shape: not gated on an active feature, idempotent, **propose-before-writing**. It is **native-first**: it orchestrates primitives the pack already has (the `documenter` skill as the workhorse, the `architect` subagent for ambiguous boundary calls, and the `pm` domain heuristic run in reverse) rather than inventing analysis machinery.

`/adopt` is a deliberate, interactive pass — **not** something `install.sh` runs automatically. Install stays mechanical; adoption needs user confirmation on domain boundaries, so it is its own step. The installer's closing message gains one line pointing existing-project users at `/adopt`.

### What "a solid base" is, in the pack's own terms

The base is the durable memory the lifecycle reads, in priority order:

| Artifact | Why it is the base | Cost |
|---|---|---|
| `CLAUDE.md` → `## Project conventions` | Highest leverage. Stops every future plan from re-deriving import style, test runner, lint, framework idioms. | Low |
| `docs/domains/<domain>.md` (the spine, not everything) | What `/feature-start` decomposition extends. Without it the domain map is re-derived per feature. | Medium |
| `docs/adr/` for genuinely contested *existing* decisions | Lets the architect detect contradictions. | Low, but see Decision 1 |

### Command shape

`/adopt [<area>]` — no argument documents the spine of the whole repo; an optional area scopes the pass to one directory/subsystem (e.g., the area the next feature will touch).

**Phase A — Survey conventions.** The documenter skill (reconciler role) surveys the repo and proposes a `## Project conventions` block for `CLAUDE.md`: language + version, package manager, test runner, lint/format/typecheck config, DI/wiring pattern, import style, error/result shape, logging/config access. **Every entry carries `file:line` evidence** — the same rule the `/plan` research phase already enforces, so no folk knowledge leaks in. (Reuses the evidence-table format from the pm skill's research phase.)

**Phase B — Discover domains.** Run pm's extend-vs-introduce heuristic *in reverse*: cluster existing code into bounded contexts. Propose the domain map to the user — a list, one line each, naming the files each context owns. The user confirms, corrects, merges, or splits. This is the cheap correction point, exactly as domain decomposition is in `/feature-start`. Invoke the `architect` only for a genuinely ambiguous boundary (the same trigger criteria as everywhere else).

**Phase C — Write domain docs.** For each confirmed domain, the documenter drafts a terse `docs/domains/<domain>.md`: current responsibilities, key types/entry points, dependencies/direction, and an **"as-built rationale"** subsection capturing *why it is shaped this way*. Propose each before writing.

**Phase D — Conventions to `CLAUDE.md`.** Write the Phase A block into the `## Project conventions` placeholder via the documenter's propose-before-write. If `CLAUDE.md` is not yet devkit-shaped, route through `/claude-md-merge` first.

**Phase E — Contested decisions → ADRs (opt-in, sparse).** See Decision 1. Default is to write **no** ADRs.

**Phase F — State + commit.** `state.md` stays `idle` (no active feature; adoption is not a feature). Propose a single commit of the produced artifacts — domain docs, `CLAUDE.md` conventions, any opt-in ADRs. Stage explicitly; never `git add -A`. Subject: `adopt: baseline domain docs + conventions`. Decline leaves the proposal visible, same contract as every other command.

### The three forks, resolved

**Decision 1 — Retroactive ADRs are a category problem; do not manufacture them.** ADRs in this pack are "immutable once accepted" and are normally drafted by the architect *at the moment of a live decision*. Reconstructing them wholesale after the fact turns them into as-built records — a different artifact wearing the ADR's clothes, and a fast route to bloat (a dozen retroactive ADRs nobody asked for). Resolution:

- The "why it is shaped this way" context lives in each domain doc's **as-built rationale** subsection (Phase C), not in ADRs.
- An ADR is written **only** where the user explicitly flags an existing decision as load-bearing *and* plausibly reversible (a future feature might want to revisit it). For those, invoke the architect, then write `docs/adr/NNNN-*.md` with `status: accepted` and an explicit note that the file documents a pre-existing decision (adoption date ≠ original decision date).
- This keeps ADR semantics clean and honours the project's no-artifact-bloat principle.

**Decision 2 — Thin base, then grow (incremental and re-runnable).** A mature project can have a dozen domains; documenting all of them up front is bloat and goes stale. The first run documents the **spine** (the few core domains + conventions). `/adopt` is idempotent: a re-run detects existing domain docs and proposes only deltas or deepening. The optional `<area>` argument scopes a pass to one subsystem — the natural move is "adopt the area my next feature touches" rather than the whole repo at once.

**Decision 3 — Dedup with plan-time research.** Once `/adopt` captures conventions into `CLAUDE.md`, the `/plan` research phase must **cite the captured conventions instead of re-deriving them**. This is a small edit to the pm skill's research section: when a convention is already recorded in `CLAUDE.md` with evidence, cite it; only research what is not yet captured (and, when research surfaces a genuinely new convention, that is a `/checkpoint`-worthy `CLAUDE.md` amendment). Without this edit, adoption captures conventions that the plan then ignores, and the pass pays no downstream dividend.

## Alternatives considered

**Do nothing; let plan-time research carry it.** The research phase already discovers conventions per feature. Rejected: it re-discovers them every time, captures nothing durable, and does nothing for the domain map or the architect's contradiction check. The first feature on a brownfield project is materially worse than the tenth, for no reason other than missing memory.

**Make `install.sh` generate the base automatically.** Rejected: domain-boundary calls require user judgment, and silent generation violates propose-before-write. Install must stay mechanical and non-interactive (it runs in CI, with `--dry-run`, etc.). Adoption is interactive by nature.

**Reuse `/checkpoint` for adoption.** `/checkpoint` is feature-scoped (it reconciles the *active* feature's docs against repo state). Adoption has no active feature and a different job (create baseline memory, not reconcile a feature). Overloading `/checkpoint` would blur a clean command. Rejected.

**A new `adopter` skill or subagent.** Rejected as unnecessary surface. The documenter already owns "write/reconcile durable docs," the architect already owns "ambiguous boundary calls," and the pm already owns the domain heuristic. `/adopt` is orchestration over existing primitives — consistent with native-first and the pack's bounded surface area.

## Consequences

**Positive:**
- A brownfield project reaches the same "solid base" a greenfield project grows to — domain map, captured conventions, optional decision records — in one deliberate pass.
- The first feature on an adopted project is as well-grounded as a later one.
- No new skill/subagent; surface grows by one housekeeping command + two small edits (pm research-citation; installer closing message).
- Settles the long-outstanding "second-project install is the only honest test that the pack stands on its own" item — the second-project dogfood *is* the `/adopt` dogfood.

**Negative / risks:**
- **Over-documentation/bloat.** Mitigated by spine-first (Decision 2), propose-before-write, and the user confirming the domain map before any doc is written.
- **As-built docs go stale.** Domain docs are already living (documenter updates them at `/feature-merge`); the adoption pass produces a *starting point*, not a frozen record.
- **Hallucinated conventions.** Mitigated by the `file:line`-evidence rule (Phase A) — no entry without a citation, same discipline as `/plan`.
- **Scope creep into "rewrite the project's docs."** `/adopt` produces only the three base artifacts; it is not a docs-generation tool. README/user-doc generation stays out of scope.

**Open questions:**
- Whether `install.sh` should create empty `docs/{domains,adr,specs,summaries}/` or leave creation to `/adopt`/`/feature-start` (current commands `mkdir -p` on demand). Leaning: leave on-demand; do not create empty dirs.
- Exact heuristic for "spine" domain selection on a large repo (top-level package boundaries? import-coupling clusters? user-named?). Refine against the dogfood.
- Whether a scoped `/adopt <area>` re-run should be allowed to *split* a previously-confirmed domain. Probably yes, via the same propose-before-write path; confirm in dogfood.

## Build slice

This is **slice 7**, added after the six-slice core (it can only be validated once the lifecycle it feeds exists).

**Build:**
- `pack/commands/adopt.md` — the command (Phases A–F above).
- Edit `pack/skills/pm/SKILL.md` research section — cite captured `CLAUDE.md` conventions instead of re-deriving (Decision 3).
- Edit `install.sh` closing message — point existing-project users at `/adopt`.
- Edit `pack/devkit-orientation.md` "Housekeeping commands" — document `/adopt` alongside `/claude-md-merge`.
- Follow-up doc edits (design-currency): add `/adopt` to `docs/design/inventory-and-build-order.md` and update this project's `CLAUDE.md` status section.

**Dogfood task:** Run `/adopt` on a real second project (not chungar). Verify: Phase A conventions carry `file:line` evidence; the proposed domain map is genuinely useful and correctable; domain docs are terse and accurate; no ADRs written unless a decision is flagged; a subsequent `/feature-start` on that project orients against the produced docs and a `/plan` cites the captured conventions rather than re-deriving them. Re-run `/adopt` and confirm idempotence (proposes deltas, not duplicates).

**Why slice 7 last:** Adoption only pays off if the lifecycle that consumes the base exists and is validated. Building it earlier would mean dogfooding a base with nothing to read it.
