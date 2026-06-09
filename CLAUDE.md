# CLAUDE.md

This file is for Claude Code working *on* this project — the authoring of a compositional skill-pack for Claude Code itself. It is **not** the CLAUDE.md that will ship with the pack to end users; that's a separate deliverable.

## What this project is

A skill-pack for Claude Code that enforces a specific engineering shape: domain-driven feature breakdown, spec-first development, TDD/SOLID/Clean Architecture, branch-per-feature, and living documentation. Composes the best of Obra Superpowers (TDD discipline), SpecKit (spec rigor), and GSD (branch loop) using native Claude Code primitives rather than building a parallel framework.

The design is fully documented in `docs/design/`. Read those before authoring anything:

- `docs/design/0001-skill-pack-architecture.md` — the architecture and rationale
- `docs/design/comparison-table.md` — why this synthesis instead of extending an existing framework
- `docs/design/walkthrough.md` — what the workflow looks like end-to-end
- `docs/design/inventory-and-build-order.md` — every component and the slice-by-slice build plan

If a question can be answered from those four docs, answer it from those four docs. They are the source of truth for design decisions.

## The shape of the pack (summary)

**Subagents (3):** `architect`, `tester`, `security-reviewer` — each gets fresh context because isolation is load-bearing for what they do.

**Skills (3):** `engineer`, `documenter`, `pm` — instructions the main thread follows; no isolated context needed.

**Slash commands (5):** `/feature-start`, `/plan`, `/build`, `/checkpoint`, `/feature-merge`.

**Hook (1):** `doc-drift-detector` — `PostToolUse` warning system for edits outside active spec scope.

**Memory layout:** `docs/` for durable human-first artifacts (specs, plans, ADRs, domains, summaries) + `.claude/state.md` as the machine-first working pointer.

## Current build status

**All six core slices are complete and dogfood-validated; slice 7 (commit-discipline polish pass) is applied but not yet dogfood-validated.** Remaining work is documentation/scripting + slice-7 validation — see "Pack-completion work outstanding" below.

**Dogfood target:** `chungar` (Google ADK + LiteLLM personal-assistant agent at `/Users/bryanlorette/Code/rubrik-chungarsih-agent`).

**Slice 6 (closeout and gate):** Authored `pack/agents/security-reviewer.md` (fresh-context security pass with 13 categories + 5 severity buckets + structured output format), `pack/commands/feature-merge.md` (three sequential gates: tests → docs reconciliation → security review, then summary authoring + supersede + merge proposal with explicit user confirmation), and extended `pack/skills/documenter/SKILL.md` with the "Summary authoring" subsection. Dogfooded end-to-end on chungar's `feature/notes-write-and-delete`. See `docs/validation/slice-6.md`.

**Slice 7 (commit-discipline polish, applied 2026-06-09):** Surfaced by the chungar follow-up feature `notes-write-and-delete-services-and-tools`, which ran through the pack with no commit-discipline guidance and landed all 5 build steps + spec + plan in a single 1,878-line mega-commit (`c81bda0`). Root cause: pre-slice-7 pack had zero mentions of "commit" anywhere in engineer skill, `/build`, `/feature-start`, `/plan`, or `CLAUDE.md.template`; `/checkpoint` explicitly said "do not commit." Five surgical edits applied: (A) engineer skill — new Verify substep 5 "Commit the step" + Karpathy "Reversible = git revert test" rewrite; (B) `/build` — "After the step" rewritten to defer-and-reinforce engineer substep + halt condition for stage failure + stale Phase-idle / "slice 1" comment cleaned up; (C) `/feature-start` Phase H and `/plan` Phase G — commit-and-handoff stage with subject/body shape + halt condition; (D) `/checkpoint` — "do not commit" replaced with propose-then-easy-decline; (E) `CLAUDE.md.template` — new "Commit cadence" section with full-feature commit table + "stage explicitly, propose never silent" rules. **Not yet dogfood-validated** — chungar's next feature is the validation opportunity.

**What exists (full pack):**
- Design docs (`docs/design/`)
- `pack/` — six core slices + slice-7 polish edits:
  - Slice 1: `pack/skills/engineer/SKILL.md`, `pack/agents/tester.md`, `pack/commands/build.md`, `pack/CLAUDE.md.template`, `pack/state.md.template`
  - Slice 2: `pack/skills/pm/SKILL.md`, `pack/agents/architect.md`, `pack/commands/feature-start.md`
  - Slice 3: extensions to `pm` and `engineer` skills (plan-time behaviors), `pack/commands/plan.md`
  - Slice 4: `pack/skills/documenter/SKILL.md`, `pack/commands/checkpoint.md`; minor extensions to `pm` + `engineer` skills + `CLAUDE.md.template` + `state.md.template`
  - Slice 5: `pack/hooks/doc-drift-detector.py`, `pack/hooks/settings.json.fragment`; `owned_files` guidance in pm skill; "Automated guards" in `CLAUDE.md.template`
  - Slice 6: `pack/agents/security-reviewer.md`, `pack/commands/feature-merge.md`; "Summary authoring" subsection in documenter skill
  - Slice 7: edits A–E above; touches `engineer/SKILL.md`, `build.md`, `feature-start.md`, `plan.md`, `checkpoint.md`, `CLAUDE.md.template`
- Validation reports: `docs/validation/slice-1.md` through `slice-6.md` (slice-7 report pending dogfood)
- Authoring notes: `docs/authoring-notes/spec-and-plan-depth.md`
- Chungar dogfood state:
  - `master` carries the merged `notes-write-and-delete` feature (commit `e899a28`, merged 2026-06-05) plus full slice-1-through-slice-6 pack install (slice-7 edits not yet propagated to chungar's `.claude/`).
  - `feature/notes-write-and-delete-services-and-tools` — Thread B follow-up; 5 steps built (NoteQueryService, NoteWriteService, SqliteNoteRepository, tools.py, agent wiring); 101 tests passing; spec + plan approved; state.md Phase `building`; entire feature in one commit `c81bda0` (the slice-7 trigger). Ready for `/feature-merge` whenever you want to close it out.
  - `feature/notes-read-and-search` — **superseded** by `notes-write-and-delete`; branch retained per supersede mechanic.
  - Summary: `docs/summaries/notes-write-and-delete.md`. First-of-domain doc: `docs/domains/notes.md`.

## Pack-completion work outstanding

Per the "What 'done' looks like for this project" criteria (below), two items remain after slice 7 + Thread A:

1. **Slice-7 dogfood validation.** The new commit-discipline edits (A–E) have not been exercised against a real `/build` invocation. Natural test: install slice-7 pack into a target via `./install.sh` and run a small feature end-to-end. Should produce per-step commit proposals at the end of each `/build` Verify.
2. **`pack/CLAUDE.md.template`** has not been validated by a fresh install into a *non-chungar* target. Only second-project use confirms the template stands on its own.

**Done in this pass:**

- ✓ **`install.sh`** (root). Idempotent bash script with python3-via-heredoc for the JSON merge. Flags: `--project-name`, `--description`, `--mainline`. Smoke-tested across three scenarios (fresh, re-run idempotency, no-description placeholder).
- ✓ **`README.md`** (root). Single entry point: status caveats, requirements, install + manual fallback, components map, end-to-end workflow walkthrough, memory layout, three disciplines, uninstall, pointer to design docs.

**Forward-references carried from slices 6–7** (no action required for pack completion; tracked in slice validation reports):

- **Documentation pass polish items (from slice 6):**
  - Documenter skill's cardinal-discipline section — clarify multi-doc merge-time scenario (Finding 5).
  - `/feature-merge` precondition wording — tighten the "no uncommitted changes" vs "untracked files" ambiguity (Finding 7).
  - `/feature-merge` merge-strategy fallback — elevate to a named subsection in the command spec (Finding 6).
- **Mechanism not yet exercised:** package-manifest commit surfacing in `/feature-merge` summary (slice-5 forward-reference; chungar's slice-6 dogfood had no `pyproject.toml` changes to test it against).
- **`/checkpoint` Pattern C (park)** still unexercised. Should land the next time a real park surfaces.
- **Stale `/checkpoint` language:** the "slice-5 hook (when shipped)" framing on lines 96 and 98 is now historical (hook is shipped). Worth a one-line cleanup pass.

**Natural next dogfood:** propagate slice-7 edits into chungar's `.claude/`, then either (a) run `/feature-merge` on the in-progress `feature/notes-write-and-delete-services-and-tools` to exercise the gate trio + slice-6 polish items + slice-7 `/checkpoint` commit proposal, or (b) start a small new feature on chungar (e.g., the deferred `add ruff + mypy + pre-commit` follow-up) to exercise slice-7 edit-A end-to-end at `/build` time.

## Working principles for this project

These are non-negotiable for the *authoring work*, not just the eventual pack:

1. **Native-first.** Use Claude Code's actual primitives (subagents, skills, slash commands, hooks, CLAUDE.md) before inventing anything new. If a problem can be solved by a built-in mechanism, that's the answer. The pack exists to compose primitives, not replace them.

2. **Dogfood after every slice.** Each of the six slices is independently usable. After completing a slice, validate it on a real feature in a real project before moving on. Do not author slice N+1 until slice N has survived contact with reality.

3. **Design docs are the contract.** If implementation diverges from the design docs, one of two things must happen before continuing: (a) update the design doc to reflect the new decision (with rationale), or (b) revert the implementation to match the design. Do not allow silent divergence. This is the same doc-currency discipline the pack itself will eventually enforce — practice it during authoring.

4. **TDD on the skill content where it makes sense.** Skills are markdown, not code, but they can still be tested behaviorally: write a small example task that exercises the skill, predict the expected behavior, then load the skill in a fresh Claude Code session and run the task. If behavior diverges from prediction, the skill needs revision — not the prediction.

5. **Small reversible steps.** The Karpathy discipline applies to authoring too. Author one component at a time. Commit. Validate. Move on. Resist the urge to write the whole skill-pack in one session and review at the end.

6. **No artifact bloat.** The walk-through committed to four durable docs per feature. If, during authoring, an urge to produce a fifth durable artifact appears, that's a signal to either (a) consolidate into an existing artifact or (b) update the design doc with a reasoned argument for why the fifth is necessary. Don't just add it.

## Directory layout (this project)

```
.
├── CLAUDE.md                       (this file)
├── README.md                       (high-level project overview for humans)
├── docs/
│   ├── design/                     (the four design docs — read-mostly)
│   │   ├── 0001-skill-pack-architecture.md
│   │   ├── comparison-table.md
│   │   ├── walkthrough.md
│   │   └── inventory-and-build-order.md
│   ├── authoring-notes/            (decisions made during authoring)
│   └── validation/                 (dogfood reports per slice)
├── pack/                           (the skill-pack itself, the actual deliverable)
│   ├── CLAUDE.md.template          (the CLAUDE.md that ships with the pack)
│   ├── skills/
│   │   ├── engineer/SKILL.md
│   │   ├── documenter/SKILL.md
│   │   └── pm/SKILL.md
│   ├── agents/
│   │   ├── architect.md
│   │   ├── tester.md
│   │   └── security-reviewer.md
│   ├── commands/
│   │   ├── feature-start.md
│   │   ├── plan.md
│   │   ├── build.md
│   │   ├── checkpoint.md
│   │   └── feature-merge.md
│   └── hooks/
│       └── doc-drift-detector.sh   (or .js, .py — TBD when authoring slice 5)
└── examples/                       (fabricated example projects used for dogfood)
```

The split between `docs/` and `pack/` is deliberate: `docs/` is about the project of building the pack; `pack/` is the pack. When dogfooding, the contents of `pack/` get copied into a real target project's `.claude/` directory.

## Conventions for this project's docs

- Design docs in `docs/design/` are versioned by edit, not by filename. Change history goes in git, not in `-v2.md` filenames.
- Authoring notes capture *why a skill was written this way* when the reasoning isn't obvious from the skill itself. They're not required for every skill — only for non-obvious choices.
- Validation reports document what happened during dogfooding: what worked, what didn't, what changed in the pack as a result. One per slice.

## Conventions for the pack itself (`pack/`)

Skills follow Claude Code's `SKILL.md` format with YAML front-matter:

```yaml
---
name: <skill-name>
description: <triggering conditions in plain language>
---
```

Subagent files use the standard Claude Code agent definition format.

Slash command files use the standard Claude Code command format.

Where Claude Code's primitives are ambiguous or evolving, document the choice in an authoring note. Do not hard-code assumptions that might be wrong; prefer comments like `# When Claude Code's subagent format stabilizes, revisit this.`

## What "done" looks like for this project

- All six slices completed and validated
- Pack has been used end-to-end on at least one real feature beyond dogfood
- The pack's own CLAUDE.md template (`pack/CLAUDE.md.template`) is written and tested
- README in this project explains how to install the pack into a target project

This project is finished when someone unfamiliar with the design can install the pack and use it without reading any of the four design docs. The pack must stand on its own.

## When in doubt

1. Re-read the relevant design doc.
2. If the design doc doesn't answer it, the design doc is incomplete — surface that gap explicitly rather than guessing.
3. Never silently extend the design. Either ask, or update the design doc with rationale.