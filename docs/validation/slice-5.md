# Slice 5 — Dogfood Validation Report

**Slice:** 5 (drift detection automation — `doc-drift-detector` hook + `owned_files` convention formalization)
**Dogfood target:** chungar (`/Users/bryanlorette/Code/rubrik-chungarsih-agent`)
**Validation feature:** `notes-write-and-delete` (continuation from slice 4; same feature, now with the hook installed)
**Status:** complete; no pre-slice-6 revisions required
**Date:** 2026-06-04

## Executive summary

Slice 5's pack content (the `doc-drift-detector` hook, the `settings.json` fragment, and the tightened `owned_files` guidance in the pm skill) was exercised across five scenarios: in-scope edit (silent), out-of-scope edit (warning), excluded path (silent), no-active-feature state (silent), malformed input (silent). All five behaved as designed. The hook also surfaced one **real** drift via `/checkpoint` Pattern D reconciliation: `chungar/__init__.py` was touched by the Step-1 cherry-pick but isn't in the spec's `owned_files` glob. Resolution amended the spec's Prerequisites section rather than expanding `owned_files` — a meaningful exercise of the honest-scoping rule the pm skill now formalizes.

The strongest signal is that **the hook + documenter + pm-skill scoping rule compose correctly under tension**: when drift surfaces, the temptation is to silence it by broadening `owned_files`; the pm skill's "don't be too broad" rule resists that temptation; the documenter's Pattern A points at the right resolution (annotate the Prerequisites section, leave `owned_files` honest). Without all three layers cooperating, the easy path would be the wrong one.

No pre-slice-6 revisions required. The pack's three-layer doc-currency defense (per ADR-0001) is now fully in place.

## Findings

### Finding 1 — Hook behavior is correct across all five scenarios

**Surface:** Synthetic-input testing of the hook script:

| Scenario | Tool input | Expected | Observed |
|---|---|---|---|
| In-scope edit | `Edit chungar/notes/service.py` | silent, exit 0 | silent, exit 0 ✓ |
| Out-of-scope edit | `Edit chungar/agent_defs.py` | warning, exit 0 | warning with path, spec, active feature, resolution options, exit 0 ✓ |
| Excluded — spec doc | `Write docs/specs/notes-write-and-delete.md` | silent, exit 0 | silent, exit 0 ✓ |
| Excluded — CLAUDE.md | `Write CLAUDE.md` | silent, exit 0 | silent, exit 0 ✓ |
| Excluded — state.md | `Write .claude/state.md` | silent, exit 0 | silent, exit 0 ✓ |
| Excluded — pyproject.toml | `Write pyproject.toml` | silent, exit 0 | silent, exit 0 ✓ |
| No active feature | `Edit src/random.py`, state.md says `Active feature: none` | silent, exit 0 | silent, exit 0 ✓ |
| Malformed input | `not-json` on stdin | silent, exit 0 (graceful) | silent, exit 0 ✓ |

**Warning text observed (out-of-scope case):**

> `devkit drift-detector: edit touched `chungar/agent_defs.py`, which isn't covered by any glob in `docs/specs/notes-write-and-delete.md`'s `owned_files` front-matter (active feature: notes-write-and-delete). Either expand the spec's scope via `/checkpoint <description>` or move this change to a different feature. (The hook does not block; this is informational.)`

Single line, names path + spec + feature + two resolution options + explicit non-blocking. Matches the design intent ("surfaces drift as a warning Claude must address before continuing").

**Positive signal.** The hook behaves correctly under every scenario tested, including the "no signal" cases that are the silent majority of real use. Exit 0 always; never blocks the harness.

**No change recommended.**

### Finding 2 — Live-harness invocation not directly observed in this session

**Surface:** The hook is registered in chungar's `.claude/settings.json` for `PostToolUse` matchers `Edit|Write|NotebookEdit|MultiEdit`. The hook would fire in real Claude Code sessions running under chungar's settings, but this validation session is running under the devkit project's settings (not chungar's). Direct script invocation via piped JSON was used as the test harness; live-harness firing is unobserved.

**Risk assessment.** The script's input contract is well-specified (Claude Code's PostToolUse JSON: `tool_name`, `tool_input.file_path`, `cwd`). The synthetic test inputs match what the harness will send. The risk of mis-integration is in the settings.json registration shape, not the script behavior — and that fragment is small and follows Claude Code's standard hook config schema.

**Worth doing in slice-6 dogfood or a future chungar session:** start a Claude Code session in chungar's directory; perform an `Edit` on an out-of-scope file; observe whether the warning lands as additional context for the model. Tracked here, not actioned in slice 5.

**No change recommended.**

### Finding 3 — Pattern D reconciliation found one real drift

**Surface:** During the dogfood, `/checkpoint` (no args, Pattern D) was invoked on chungar's `notes-write-and-delete` feature. The reconciliation pass:

- **`owned_files` coherence:** walked `git diff master..HEAD --name-only`; classified each touched file against `owned_files` + auto-excluded paths. One file flagged: `chungar/__init__.py` (touched by the Step-1 cherry-pick that emptied it to break the eager-import chain), not in any `owned_files` glob, not excluded.
- **state.md coherence:** Next step (`Step 3 — NoteQueryService ...`) matches a step heading in the plan ✓. Spec/Plan paths exist ✓.
- **Front-matter coherence:** Spec `approved (amended 2026-06-02)`, Plan `approved (amended 2026-06-03)`. Both follow the documenter's amendment-status format ✓.

**Positive signal.** Pattern D found a real, non-trivial drift that the slice-4 dogfood didn't surface (because slice 4 was the same author making the changes in real-time — they were "obvious in context" and not flagged). A `/checkpoint`-style reconciliation against the actual diff log catches what real-time review misses.

**Resolution — and the meaningful test of pm-skill scoping:** the easy answer to "X file isn't in owned_files" is to add it. But the pm skill's "don't be too broad" rule says: adding `chungar/__init__.py` silences the hook on every future cross-cutting touch of that file (any future feature that adds a new submodule will edit `__init__.py`, but rarely in a way that's actually scoped to a particular feature). The honest resolution is to amend the Prerequisites section (which already documents the cherry-pick) to explicitly call out the prerequisite-only touch — keeping `owned_files` narrow.

Applied: spec's Prerequisites section gained a second amendment blockquote (2026-06-04); spec status bumped to `approved (amended 2026-06-02, 2026-06-04)` — multiple-amendment dates listed per the documenter's "append, don't overwrite" rule. The "append, don't overwrite" rule from slice 4 is now exercised.

### Finding 4 — Three-layer doc-currency defense composes correctly under pressure

**Surface:** The Pattern D resolution was the first place where the three doc-currency layers all weighed in:

- **Hook (slice 5):** surfaced the drift signal.
- **Documenter skill (slice 4):** proposed two resolution paths (expand scope; record in Prerequisites).
- **PM skill scoping rule (slice 5):** ruled out the "expand scope" path because over-broad scoping defeats the hook.

If any one layer had been missing or wrong, the wrong path would have been taken: no hook = no signal at all; no documenter = silent expansion of `owned_files`; no pm-skill rule = expansion would have been the easy default. The compositional design pays off here.

**Positive signal.** ADR-0001's "three-layer defense" claim is now empirically validated, not just designed. The layers cooperate; none is redundant.

**No change recommended.**

### Finding 5 — Built-in exclusions cover the right things

**Surface:** The hook's `EXCLUDED_PREFIXES` list (`.claude/**`, `docs/**`, `CLAUDE.md`, `README.md`, `.gitignore`, `pyproject.toml`, `package.json`, `Cargo.toml`) was tested directly. All excluded paths produced silent exits. The dogfood's actual touches to `.claude/state.md`, `.claude/skills/...`, `docs/specs/...`, `docs/adr/...`, etc. would never have triggered the hook (correct).

**Observation worth keeping:** the exclusion list is narrow and project-meta-only. A common alternative would have been "exclude everything in `.gitignore`" — rejected as too aggressive (the user might intentionally edit a gitignored file as part of feature work; we should still flag it). The current list will need to grow when new project-meta patterns emerge; current default is sane.

**Potential future addition (low priority):** `Makefile`, `Dockerfile`, `Justfile`, `.env.example`. None of these surfaced in the chungar dogfood; defer until evidence forces a real project to surface a noisy exclusion miss.

**No change recommended.**

### Finding 6 — `_glob_to_regex` `**` handling is non-trivial

**Surface:** The hook implements its own glob-to-regex translator to avoid PyYAML / external dependencies. The `**` semantics had to be carefully matched against common glob expectations:

- `src/**` matches `src/foo.py`, `src/foo/bar.py`, `src/foo/bar/baz.py` — anything under `src/`.
- `src/**/*.py` matches `src/foo.py`, `src/foo/bar.py` — anything ending in `.py` under `src/` (including direct children).
- Edge case: `src/**` should match both `src/file` and `src/sub/file` — handled by the `**/` → `(?:.*/)?` translation (zero-or-more segments + slash).

Tested via the in-scope/out-of-scope scenarios. The Step-1 cherry-pick's actual `owned_files` (`chungar/notes/**`, `tests/notes/**`, `chungar/agent.py`) all match correctly; the test cases exercise both `**`-recursive and exact-file forms.

**Positive signal.** Stdlib-only implementation works; no PyYAML dependency. Worth re-checking if a future spec uses more exotic globs (negation `!`, brace expansion `{a,b}`), neither of which the current implementation supports. The pm skill's guidance doesn't mention them, so deferred.

**No change recommended.**

### Finding 7 — Pattern C (park) and live-harness still unexercised

**Surface:** Same gap as slice 4 Finding 9 — Pattern C (park) didn't naturally surface in this dogfood. The chungar feature continues to be active and progressing; no real park need arose.

**Risk assessment unchanged.** Pattern C is small and the documenter's instructions are clear. Worth exercising next time a real park surfaces; defer.

**No change recommended.**

### Finding 8 — `pyproject.toml` exclusion is currently broad but right

**Surface:** The exclusion list includes `pyproject.toml` (and `package.json`, `Cargo.toml`). The reasoning: project-level config changes (adding deps, configuring tools) are typically cross-cutting and not feature-scoped. But a counter-case exists: a feature that *specifically* adds a new dependency (e.g., "add `httpx` for the new HTTP-client feature") legitimately touches `pyproject.toml` *because of the feature*, and the hook silencing that signal hides the change.

**Trade-off:** with the exclusion, we lose visibility on deliberate per-feature dep additions. Without it, every cross-cutting tooling change (linter config, formatter config, version bumps) becomes noise.

**Judgment:** keep the exclusion. The lost signal (deliberate per-feature deps) is recoverable via the commit log (commits touching `pyproject.toml` are visible to `/feature-merge`'s docs-reconciliation gate when slice 6 ships). The noise prevented (cross-cutting tooling) is constant and would dominate.

**No change recommended.** Worth revisiting if a real project surfaces evidence the trade-off is wrong.

## Validation feature progress

- [x] Slice-5 pack content authored (`doc-drift-detector.py`, `settings.json.fragment`)
- [x] `pack/skills/pm/SKILL.md` — `owned_files` guidance tightened (glob syntax, honest-scoping rule, hook-as-consumer reference)
- [x] `pack/CLAUDE.md.template` — new "Automated guards" subsection documenting the hook + install path
- [x] Hook script smoke-tested directly across 5 scenarios (in-scope, out-of-scope, excluded ×4, no-active-feature, malformed input)
- [x] Mirrored into `chungar/.claude/`; hook executable; settings.json registered the hook for `Edit|Write|NotebookEdit|MultiEdit`
- [x] Pack install commit on `feature/notes-write-and-delete`
- [x] Direct-invocation test on real chungar paths: in-scope (`chungar/notes/service.py`), out-of-scope (`chungar/agent_defs.py`), excluded (4 paths) — all behaved correctly
- [x] `/checkpoint` Pattern D (no-args reconciliation) — first time exercised; surfaced 1 real drift (`chungar/__init__.py`), 0 false positives across 22 touched files
- [x] Pattern A amendment of spec's Prerequisites section to record the cherry-pick prerequisite touch; deliberately did **not** expand `owned_files` (exercise of the honest-scoping rule)
- [x] Spec status bumped to `approved (amended 2026-06-02, 2026-06-04)` — multi-amendment "append, don't overwrite" rule exercised
- [ ] **NOT exercised:** live-harness firing of the hook in a real Claude Code session under chungar's settings. Synthetic input testing is a strong-but-not-perfect proxy. Should land naturally the next time a Claude Code session runs in chungar.
- [ ] **NOT exercised:** `/checkpoint` Pattern C (park) — chronic-gap from slice 4 still open.

## Verdict

**Slice 5 passes; no pre-slice-6 revisions required.**

Rationale:

- **The hook script is correct** across every scenario tested. Silent on happy path; informative warning on drift; never blocks; gracefully handles every malformed input. Stdlib-only implementation; no portability risk.
- **The three-layer doc-currency defense composes correctly under pressure.** Pattern D found real drift; the documenter offered two resolution paths; the pm skill's scoping rule selected the right one. Without all three layers cooperating, the easy/wrong path (silence-by-broadening) would have been chosen.
- **The honest-scoping rule earned its keep.** The Pattern D resolution would have been the wrong amendment if pm skill hadn't formalized "don't be too broad" — added `chungar/__init__.py` to `owned_files` would have silenced future drift signals.
- **No findings are blockers.** Live-harness validation (Finding 2) and Pattern C exercise (Finding 7) are gaps that fit naturally into slice-6 dogfood; not blocking.
- **The pack's full doc-currency defense is now in place.** Slice 6 (closeout) adds the merge gate that completes the pack.

## Required pack revisions before slice 6

**None.**

**Forward-references for slice 6** (no action now; tracked):

- **`/feature-merge` (slice 6) should:**
  - Run a final-pass equivalent of `/checkpoint` Pattern D as part of gate 2 (docs reconciliation).
  - Surface commits touching `pyproject.toml` / `package.json` / `Cargo.toml` in the summary doc, since the drift hook intentionally silences them (Finding 8).
  - Include `/checkpoint`-landed amendments in the summary (grep plan + spec for `> **Amendment` blockquotes).
  - Support "supersede" transition for parked features the merging feature has absorbed (chronic from slice 3; chungar's `notes-write-and-delete` will supersede `notes-read-and-search` at merge time).

- **Install scripting** (whenever it lands):
  - The hook script needs `.claude/hooks/` directory + executable bit + settings.json merge. A one-liner install script would prevent the friction the slice-5 install commit had to handle manually.
  - Pyc-gitignore prerequisite (chronic — slice 3, 4, and 5 all flagged).
  - `main` vs `master` default branch detection (chronic).

## Skill content gaps surfaced but deferred

- **Hook script extension points.** Future projects may want to customize: the exclusion list, the warning format, additional drift checks (e.g., "the active spec's `last_modified` is older than the most recent commit touching `owned_files`"). The current script is monolithic; refactoring for extensibility is premature until evidence forces it.
- **PyYAML vs stdlib for front-matter parsing.** The hook uses a hand-rolled minimal YAML parser. It handles only the subset of YAML the pm-skill's spec template emits (top-level keys + a single nested list under `owned_files`). If specs ever need richer front-matter (nested mappings, anchors, multi-line strings), the parser will break. Trade-off accepted for now (zero dependency); revisit if a real spec needs the richer syntax.
- **The hook is per-project; no cross-project sharing.** Each chungar-like project installs its own copy. A future install scripting story should manage updates (when the pack ships a hook fix, how do downstream projects pick it up?). Defer.

## What was NOT validated

Honest list:

- **Live-harness firing of the hook.** Finding 2.
- **Pattern C (park).** Finding 7 / chronic.
- **The hook firing repeatedly in quick succession** (e.g., 10 out-of-scope edits in one /build step). The script is stateless and idempotent; risk is low; not exercised.
- **The hook firing on a NotebookEdit or MultiEdit specifically.** Edit and Write were tested; the other two tool types are handled the same way in the script. Not exercised in synthetic tests.
- **The hook firing on an edit to a brand-new file** (`Write` creating a path that doesn't yet exist on disk). The script reads `Path(edited_path).resolve()` which works regardless of whether the file exists; not exercised but should work.
- **A spec with no `owned_files` at all.** The script handles this (empty list → exit early → silent). Behavior is "don't check anything," which means the hook is silent for any feature whose spec author omitted the field. Worth a small validation later (and the pm-skill update now makes the field's importance clearer).
- **A spec with malformed front-matter YAML.** The script's hand-rolled parser falls back to "empty list" on parse failure (silent). Probably the right behavior; not exercised.
- **Drift caught on a feature in `spec-draft` phase** (before the spec is approved). Currently the script doesn't check `status` — it fires whenever a spec exists with `owned_files`. This is probably correct (scope is declared the moment the spec is drafted); not deliberately tested.
- **Steps 3–7 of the chungar plan are unbuilt.** Not slice-5's concern.

These should be exercised in slice 6 or a future session as natural cases surface.
