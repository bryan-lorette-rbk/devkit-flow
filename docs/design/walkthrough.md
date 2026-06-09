# Walk-Through: One Feature, End to End

**Purpose:** Trace a fabricated but realistic feature through every command in the skill-pack. Every artifact produced is shown in full (specs/plans) or in skeleton (everything else) so artifact volume is visible and audit-able before the inventory is committed.

**Scenario:** A small-team project for a "Reading Tracker" — a personal app that ingests books from various sources and tracks reading progress. The codebase already exists at modest size. The user wants to add a new feature: **"Goodreads import."**

The walk-through follows the user through `/feature-start` → `/plan` → `/build` → `/checkpoint` (once, mid-feature) → `/feature-merge`. Each section shows: (1) what the user types, (2) what the system does, (3) what artifacts are produced or modified.

---

## Setup state (before the feature)

```
docs/
  specs/
    user-authentication.md      (merged)
    manual-book-entry.md        (merged)
  plans/
    user-authentication.md      (merged)
    manual-book-entry.md        (merged)
  adr/
    0001-skill-pack-architecture.md
    0002-storage-sqlite-vs-postgres.md
    0003-auth-via-magic-link.md
  domains/
    auth.md
    library.md
  summaries/
    user-authentication.md
    manual-book-entry.md
.claude/
  state.md                      (currently: no active feature)
CLAUDE.md
```

`state.md` content:
```markdown
# Project state

**Active feature:** none
**Active branch:** main
**Last merge:** manual-book-entry (3 days ago)

## Open questions
- (none)
```

---

## Phase 1 — `/feature-start "Goodreads import"`

**User types:**
```
/feature-start "Goodreads import"
```

**System behavior:**
1. PM skill loads. Reads `docs/domains/` to ground the feature in existing project shape. Reads `CLAUDE.md` for project conventions.
2. PM runs a brainstorm dialogue with the user (not silent — visible, interactive). Questions like: "What does Goodreads expose — API, CSV export, scraping? Which fields matter for the library domain? What's the user trigger — manual import, scheduled sync, both? How do we handle duplicates against existing manual entries?"
3. PM proposes a domain decomposition. For this feature, plausible domains: **ingestion** (fetching from Goodreads), **mapping** (Goodreads schema → library domain), **deduplication** (against existing entries), **persistence** (storing the result).
4. Architect subagent invoked once, in fresh context, for the question: "Does this feature warrant a new bounded context, or does it extend `library`?" Returns: extends `library`; ingestion is a new application-layer concern but doesn't justify a new domain. ADR drafted.
5. Branch created: `feature/goodreads-import`.
6. Spec written to `docs/specs/goodreads-import.md`.
7. `state.md` updated.
8. **Checkpoint: user reviews spec.**

**Artifacts produced:**

`docs/specs/goodreads-import.md`:
```markdown
---
feature: goodreads-import
status: draft
branch: feature/goodreads-import
owned_files:
  - src/ingestion/goodreads/**
  - src/library/import/**
  - src/ui/import/**
related_adrs: [0004]
---

# Spec: Goodreads import

## Problem
Users with existing Goodreads libraries can't move to this app without
re-entering every book by hand. Manual entry doesn't scale past ~20 books.

## Scope
**In:** CSV-based one-shot import from Goodreads' official export, with
mapping to the existing `Book` aggregate, deduplication against existing
entries, user-reviewed conflict resolution, and atomic per-batch persistence.

**Out:** Live API integration, reading-progress import, periodic re-sync,
multi-source merge, fuzzy matching beyond the dedup rule below.

## Domains touched
- **ingestion** (new application-layer concern): parse Goodreads CSV.
  New module under `src/ingestion/goodreads/`.
- **mapping**: translate Goodreads row → internal `Book` aggregate.
  New module under `src/library/import/`.
- **deduplication**: match against existing manually-entered books.
- **library** (existing): receive imported books via existing persistence;
  no domain changes.

## Data model

### Goodreads CSV row (input — partial)
| Field | Type | Required | Notes |
|---|---|---|---|
| `Title` | string | ✓ | |
| `Author` | string | ✓ | Primary author; spacing variants common |
| `ISBN` | string | optional | `="0451524934"` quoted format; may be empty |
| `My Rating` | int 0-5 | optional | 0 means unrated |
| `Date Added` | date YYYY/MM/DD | optional | |

### Internal `Book` aggregate (existing — extended)
| Field | Type | Constraint |
|---|---|---|
| `id` | UUID | generated on import |
| `title` | str | required, max 500 |
| `author` | str | required, max 200 |
| `isbn` | str \| None | normalized: digits only |
| `rating` | int \| None | 1-5 or None (0 → None) |
| `added_at` | datetime UTC | defaults to import time if CSV field is empty |
| `source` | enum | `manual` (existing) or `goodreads-import` (new) |

## Requirements
1. **CSV upload** — accept Goodreads' official export (UTF-8, standard CSV
   with double-quoted strings and `="..."` ISBN quoting).
2. **Mapping** — translate each CSV row to a `Book` candidate. Missing
   optional fields produce a `Book` with the corresponding field `None` or
   defaulted; the row is not rejected.
3. **Dedup** — exact title+author match (normalized: lowercase, whitespace
   collapsed) against existing books. Conflicts surfaced as pairs; user
   resolves before commit.
4. **Atomic batch** — the import either commits all non-conflicted books or
   none. No half-imported state if any persist fails.
5. **User flow** — upload → preview (counts only) → per-conflict review →
   commit.

## User flow / API surface
Three HTTP endpoints under `/api/import/goodreads/`:

- `POST /upload` — multipart CSV. Returns
  `{batch_id, parsed_count, error_count}`.
- `GET /batches/<id>/preview` — returns
  `{new: [...summary], conflicts: [(new, existing)]}`.
- `POST /batches/<id>/commit` — body specifies per-conflict resolution
  (`keep_existing` / `keep_imported` / `skip`). Atomic. Returns
  `{committed_count, skipped_count}`.

## Error handling
| Case | Where | Behavior |
|---|---|---|
| Malformed CSV | Ingestion (parser) | Reject upload; return error report with line numbers. No partial parse persisted. |
| Required field missing on a row | Mapping | Skip the row, accumulate into `error_count`. Don't fail the batch. |
| Dedup conflict | Application service | Surface to user; never auto-resolve. |
| Persist failure mid-commit | Application service | Roll back the entire batch. Surface a single error. |
| Same `batch_id` committed twice | API layer | Idempotent — return the original result. |

## Clean Architecture layout
```
src/ingestion/goodreads/
  csv_parser.py            # CSV bytes → list[CsvRow] (pure)
  mapper.py                # CsvRow → Book candidate (pure)
src/library/import/
  dedup.py                 # (existing, candidates) → conflicts (pure)
  import_service.py        # orchestrates parse → map → dedup → persist
src/library/
  book.py                  # existing aggregate (no changes)
  repository.py            # existing port (no changes)
src/ui/import/
  routes.py                # the three HTTP endpoints
  views.py                 # upload + review templates
```

**Dependency direction:** `csv_parser`, `mapper`, and `dedup` are pure (no
I/O imports). `import_service` depends on the existing `BookRepository`
port. UI depends on the application service, not on the domain.

## Integration / wiring
- `import_service` constructed in the existing DI composition root
  (`src/app/wiring.ts`) with the existing `BookRepository` adapter.
- Upload payloads land in `tmp/imports/<batch_id>.csv` with a 24h TTL;
  cleanup is a separate concern, not this feature.
- UI routes receive `import_service` via the existing NestJS dependency
  injection module.

## Testing strategy
| Layer | Approach |
|---|---|
| `csv_parser` | Pure unit tests against fixture CSVs (well-formed, malformed, empty, Unicode, edge ISBN formats). |
| `mapper` | Pure unit tests with `CsvRow` fixtures; covers missing-optional. |
| `dedup` | Pure unit tests with in-memory book lists; covers case + whitespace normalization. |
| `import_service` | Uses an in-memory `BookRepository` fake. Happy path, dedup-conflict halt, persist-failure rollback. |
| API routes | Integration test against a real `import_service` with the fake repo. |
| End-to-end | One smoke: upload → preview → commit via HTTP. |

## Risks / known trade-offs
- **Author normalization is brittle.** "J.K. Rowling" vs "J. K. Rowling"
  misses. Slice ships strict; refine if real exports surface false negatives.
  (This is exactly what `/checkpoint` amends in Phase 4 below.)
- **No streaming for very large CSVs.** Loads the file into memory.
  Acceptable to ~100k rows; revisit if hit.
- **Temp file cleanup is out-of-scope.** Tracked as follow-up.

## Acceptance criteria
- [ ] CSV upload accepts Goodreads' export and reports `parsed_count` +
      `error_count`.
- [ ] Mapping skips (not rejects-batch-on) rows missing optional fields;
      missing-required accumulates into `error_count`.
- [ ] Dedup surfaces conflicts as pairs; no auto-merge ever.
- [ ] Commit is atomic: any persist failure rolls back the batch.
- [ ] Second commit of the same `batch_id` is a no-op (idempotent).
- [ ] `src/library/book.py` is unchanged (existing domain not modified).
- [ ] `csv_parser`, `mapper`, and `dedup` have zero I/O imports.
- [ ] `import_service` tests run without touching the real database.
- [ ] All new code follows TDD (tests first, in fresh context).

## Open questions
- (none after brainstorm)
```

> The spec above models a **typical** spec, not a minimum-viable one. The
> data-model, error-handling, layout, wiring, testing-strategy, and risks
> sections are load-bearing — they catch decisions that would otherwise be
> made implicitly during `/build`. Hold a section back only when there's a
> real reason to, and say so explicitly ("No persistence — no schema
> section"). See `docs/authoring-notes/spec-and-plan-depth.md` for the
> section checklist and the rule.

`docs/adr/0004-goodreads-import-as-library-extension.md`:
```markdown
# ADR-0004: Goodreads import extends library, not new bounded context

**Status:** Accepted
**Context:** Feature spec for goodreads-import asked whether ingestion warrants
a new bounded context.
**Decision:** Extend library. Ingestion is an application-layer concern
(use-case orchestrator) feeding the existing Book aggregate. No new domain.
**Consequences:** ingestion/ lives under application layer, not domain.
Mapping logic stays out of the domain layer.
```

`.claude/state.md` (updated):
```markdown
# Project state

**Active feature:** goodreads-import
**Active branch:** feature/goodreads-import
**Phase:** spec drafted, awaiting approval
**Spec:** docs/specs/goodreads-import.md
**Plan:** (not yet created)

## Open questions
- (none)
```

**User reviews spec, approves it.** Spec status changes from `draft` to `approved`.

**Artifact count this phase:** 1 spec + 1 ADR + state.md update = 2 new docs.

---

## Phase 2 — `/plan`

**User types:**
```
/plan
```

**System behavior:**
1. `/plan` reads the approved spec from `state.md`. Refuses to proceed if spec status ≠ `approved`.
2. PM + Engineer skills load. Engineer skill brings TDD/SOLID/Clean Architecture rules into the planning context.
3. Plan generation: for each domain in the spec, produce a test list, file changes, and ordering. Karpathy discipline applied — small reversible steps, each independently testable.
4. Plan written to `docs/plans/goodreads-import.md`.
5. `state.md` updated.
6. **Checkpoint: user reviews plan.**

**Artifacts produced:**

`docs/plans/goodreads-import.md`:
```markdown
---
feature: goodreads-import
status: draft
spec: docs/specs/goodreads-import.md
---

# Implementation Plan: Goodreads import

## Approach
TDD throughout. Each step below ends in a green test suite and is
independently revertable. Steps follow Clean Architecture dependency order:
pure domain logic first (mapping, dedup), then I/O boundaries (csv parser),
then orchestration (import service), then UI. Outer layers depend inward
only.

**Test runner:** `pnpm test` (vitest, configured in `vitest.config.ts`).
**Linter / formatter:** ESLint + Prettier (`pnpm lint`, `pnpm format`).
**Type-checker:** `pnpm typecheck` (tsc --noEmit).

## Conventions and constraints

Grounded in observed repo + framework facts, not generic best practices.

### Repo conventions (observed)

| Convention | Evidence | Apply how |
|---|---|---|
| **ES modules with explicit `.ts` imports** | `tsconfig.json` has `"module": "node16"`; existing `src/library/book.ts` uses `import { ... } from "./repository.ts"`. | New files use the same `.ts`-suffixed import style. |
| **Result types over thrown errors at boundaries** | `src/library/repository.ts` returns `Result<Book, RepoError>` rather than throwing. | Mapping returns `Result<Book, MappingError>` for skip-able rows. Import service uses the existing `Result` helpers in `src/shared/result.ts`. |
| **Branded types for IDs** | `BookId = Brand<string, "BookId">` in `src/library/book.ts`. | `BatchId` is a new branded type defined in `src/library/import/types.ts`. |
| **NestJS module-per-domain** | Each `src/<domain>/` ships a `*.module.ts` registering providers. | The import feature adds `src/library/import/import.module.ts`. |
| **Vitest with co-located test files** | `src/library/book.ts` + `tests/library/book.test.ts` mirror layout. | Mirror under `tests/library/import/`, `tests/ingestion/goodreads/`. |

### Project-firsts this slice introduces

- **First CSV-handling code.** Decision: stream the CSV via `csv-parse/sync`
  (already in `package.json` for a different feature). Avoids adding a new
  dependency.
- **First feature that mutates `Book` provenance.** Add a `source: "manual" |
  "goodreads-import"` discriminator to the existing `Book` type — extension
  is additive (existing rows default to `"manual"` via a one-time migration
  in step 4).

### Framework constraints (researched)

| Constraint | Source | Implication |
|---|---|---|
| **NestJS providers must be registered in a module** | NestJS DI docs; existing `src/library/library.module.ts`. | `import.module.ts` registers `ImportService` and re-exports `BookRepository` from `LibraryModule`. |
| **Vitest discovers tests via `tests/**/*.test.ts`** | `vitest.config.ts:7`. | Test files must match the glob; place them under `tests/` mirroring source. |
| **`csv-parse/sync` returns array-of-arrays by default** | csv-parse README. | Pass `{ columns: true }` to get array-of-objects keyed by header. |

## Step order

### 1. Mapping (pure, no I/O)

- **Files (new):** `src/library/import/mapping.ts`, `tests/library/import/mapping.test.ts`
- **Test list:**
  - Maps a complete Goodreads row to a `Book` candidate.
  - Handles missing ISBN (output `isbn: null`).
  - Handles missing rating (0 maps to `null`).
  - Handles missing `Date Added` (output defaults to `addedAt: now()` —
    inject a clock to keep the function pure).
  - Returns `Err(MappingError.MissingRequired)` for rows missing `Title` or
    `Author`. Does not throw.
- **Conventions applied:**
  - Return type is `Result<Book, MappingError>` per repo's boundary
    convention.
  - `BookId` generated via `crypto.randomUUID()` injected as a parameter
    (keeps the function pure-and-testable).
  - ESLint rule `no-restricted-imports: ["fs", "path", "net"]` enforces no
    I/O imports in this file.
- **Why first:** pure function, no dependencies, validates the schema
  contract. Feeds every later step.

### 2. CSV parsing (I/O boundary)

- **Files (new):** `src/ingestion/goodreads/csv-parser.ts`, `tests/ingestion/goodreads/csv-parser.test.ts`
- **Test list:**
  - Parses a well-formed Goodreads CSV (fixture in `tests/fixtures/`).
  - Rejects malformed CSV with `Err({ kind: "parse", line: N, message })`.
  - Handles `="..."` ISBN quoting from Goodreads.
  - Handles UTF-8 BOM at file start.
  - Empty file returns `Ok([])`, not an error.
- **Conventions applied:**
  - Uses `csv-parse/sync` (already in `package.json`); no new dep.
  - Filesystem access wrapped behind a `ReadFile` port; tests pass a
    stub that returns string buffers. Keeps the parser file itself
    dependency-free at the type level.
  - Returns `Result<CsvRow[], ParseError>`.
- **Why second:** feeds mapping. Depends only on the filesystem abstraction.

### 3. Deduplication (pure, domain logic)

- **Files (new):** `src/library/import/dedup.ts`, `tests/library/import/dedup.test.ts`
- **Test list:**
  - Exact title+author match flagged as conflict.
  - Case-insensitive comparison.
  - Whitespace-collapsed comparison ("J.K. Rowling" vs "J. K. Rowling"
    flagged — though spec acknowledges this is fragile; see Risks).
  - Returns conflict pairs `[ImportedBook, ExistingBook][]`, does not
    auto-resolve.
  - Empty existing list returns no conflicts regardless of input.
- **Conventions applied:**
  - Pure function — no `fs`/`net`/clock dependency.
  - Output type `DedupResult = { fresh: Book[]; conflicts: Conflict[] }`
    defined in `src/library/import/types.ts`.
- **Why third:** needs `Book` from step 1; pure logic; doesn't need parsing.

### 4. Import orchestrator (application service)

- **Files (new):** `src/library/import/import-service.ts`, `tests/library/import/import-service.test.ts`, `src/library/import/import.module.ts`
- **Test list:**
  - Happy path: parses fixture CSV → maps → dedups → persists; verifies
    `committedCount` and zero conflicts.
  - Dedup conflict halts before persist; no rows written.
  - Persist failure rolls back the batch (uses `BookRepository`'s existing
    transactional API).
  - Empty CSV is a no-op (returns `{ committed: 0, errors: 0 }`).
  - Same `batchId` committed twice is idempotent (returns the original
    result, no re-write).
- **Conventions applied:**
  - `ImportService` registered as a NestJS provider in `import.module.ts`.
  - Depends on `BookRepository` injected via constructor (NestJS DI
    pattern; matches existing services).
  - Tests use an in-memory `InMemoryBookRepository` fake — already exists
    at `tests/library/fakes/in-memory-book-repository.ts` for the existing
    feature.
- **Why fourth:** orchestrates 1–3; depends on existing persistence.

### 5. UI surface (review + commit)

- **Files (new):** `src/ui/import/upload-route.ts`, `src/ui/import/preview-route.ts`, `src/ui/import/commit-route.ts`, `src/ui/import/views/*.tsx`, `tests/ui/import/*.test.ts`
- **Test list:**
  - `POST /upload` accepts multipart CSV and returns `{ batchId,
    parsedCount, errorCount }`.
  - `GET /batches/:id/preview` returns `{ new: [...], conflicts: [...] }`.
  - `POST /batches/:id/commit` with resolutions returns `{ committed,
    skipped }`.
  - Upload control rejects non-CSV files client-side.
  - Commit button is disabled in the React view until all conflicts have
    a resolution.
- **Conventions applied:**
  - Routes follow the existing controller pattern in
    `src/ui/library/library.controller.ts`.
  - React views use the existing component library in `src/ui/components/`.
- **Why last:** depends on stable backend contract from step 4.

## Acceptance mapping (spec → plan)

| Spec acceptance criterion | Step(s) |
|---|---|
| CSV upload accepts Goodreads' export, reports counts | 2 + 5 |
| Mapping skips rows missing optional fields | 1 |
| Dedup surfaces conflicts; no auto-merge | 3 + 5 |
| Commit is atomic; persist failure rolls back | 4 |
| Idempotent second commit | 4 |
| `src/library/book.ts` unchanged in domain shape | every step (verified by review) |
| `csv_parser`, `mapper`, `dedup` have zero I/O imports | 1 + 2 + 3 (ESLint rule) |
| `import_service` tests run without real DB | 4 |
| TDD throughout | every step |

## SOLID / Clean Architecture notes (cross-cutting)

- Mapping and dedup are pure → testable without mocks.
- CSV parser depends on a `ReadFile` port, not direct `fs` calls.
- Import service depends on `BookRepository` port, not the concrete repo.
- UI depends on the application service, not on the domain.
- ESLint `no-restricted-imports` enforces the dependency direction at lint
  time, not just at review time.

## Out-of-plan changes that may surface

- **`Book.source` discriminator** is an additive change to the existing
  domain type. Migration: one-time SQL backfill `UPDATE books SET source =
  'manual' WHERE source IS NULL`. Tracked in step 4.
- **Lint rule for `no-restricted-imports`** is added once in `.eslintrc`,
  scoped to `src/library/import/`. Not per-step.
```

`.claude/state.md` (updated):
```markdown
# Project state

**Active feature:** goodreads-import
**Active branch:** feature/goodreads-import
**Phase:** plan drafted, awaiting approval
**Spec:** docs/specs/goodreads-import.md (approved)
**Plan:** docs/plans/goodreads-import.md
**Next step:** Step 1 — mapping

## Open questions
- (none)
```

**User reviews plan, approves it.** Plan status → `approved`.

**Artifact count this phase:** 1 plan + state.md update = 1 new doc.

---

## Phase 3 — `/build`

**User types:**
```
/build
```

**System behavior:**
1. `/build` reads `state.md`, loads the plan, identifies "next step." Refuses if plan status ≠ approved.
2. For each step in the plan, the loop is:
   - Engineer skill announces step.
   - Tester subagent invoked in **fresh context** with only the test list and the spec — not the existing implementation. Writes failing tests. Returns test files.
   - Main thread (Engineer skill active) writes implementation to make tests pass. SOLID checklist applied to the diff.
   - Engineer skill reviews diff against Clean Architecture rules. If layering violated, refactor before proceeding.
   - `state.md` updated: step N complete, current diff hash recorded.
   - Hook (`PostToolUse`) fires after each Edit, surfaces drift warnings if any.
3. After each step, brief pause for user — silent unless something needs attention.

**Walking through step 1 in detail (mapping):**

- Engineer skill: "Starting step 1: mapping. Invoking tester for test list."
- Tester subagent (fresh context): writes 5 tests for `mapping.ts` per the plan's test list. Returns test file.
- Engineer skill: writes `mapping.ts` to make tests pass. Iterates red → green. Refactors for SOLID once green.
- Hook fires on `Edit src/library/import/mapping.ts`. Checks active spec's `owned_files` — match. No drift warning (file is in scope).
- `state.md` updated: step 1 complete.

Steps 2–5 follow the same loop. Hook fires on each edit; no drift because all files match `owned_files` in the spec.

**Artifacts produced or modified:**

- Source files per the plan (mapping.ts, csv-parser.ts, dedup.ts, import-service.ts, UI files)
- Test files corresponding to each
- `.claude/state.md` — updated after each step

**No new docs.** All durable docs (spec, plan, ADRs) already exist; build doesn't generate them unless something unexpected forces an ADR (which would trigger an architect subagent invocation and produce ADR-0005 or similar).

**Artifact count this phase:** 0 new durable docs in the happy path; many source + test files.

---

## Phase 4 — `/checkpoint` (mid-feature, after step 3)

**Scenario:** While building step 3 (dedup), the user realizes the spec's "exact title+author match" requirement is too strict — real Goodreads exports have author name variations ("J.K. Rowling" vs "J. K. Rowling"). User wants to update the spec mid-feature.

**User types:**
```
/checkpoint

The dedup logic needs fuzzy matching on author names — Goodreads exports
inconsistent spacing. Update spec and plan.
```

**System behavior:**
1. `/checkpoint` invokes Documenter skill.
2. Documenter reads `state.md`, spec, plan, and the user's note.
3. Documenter proposes spec update: requirement 3 changes from "exact match" to "normalized match (whitespace + case)". Plan step 3's test list gets two new tests. Asks user to confirm before writing.
4. User confirms. Documenter applies edits to both spec and plan, with `last_updated` front-matter.
5. `state.md` notes the checkpoint and the change.

**Artifacts modified:**

`docs/specs/goodreads-import.md` — requirement 3 updated; `status: approved (amended)`.
`docs/plans/goodreads-import.md` — step 3 test list extended.
`.claude/state.md` — checkpoint logged.

**No new docs.** Existing docs amended in place. If the change had been more substantial (new domain, architectural shift), an ADR would have been produced.

**Artifact count this phase:** 0 new docs; 2 modified.

---

## Phase 5 — `/feature-merge`

**User types:**
```
/feature-merge
```

**System behavior:**
1. `/feature-merge` blocks on three gates in order:
   - **Gate 1: tests pass.** Engineer skill runs the test suite. If red, halt.
   - **Gate 2: doc reconciliation.** Documenter skill compares spec/plan against actual repo state. If drift, halt and prompt for resolution.
   - **Gate 3: security review.** Security-reviewer subagent runs in fresh context. Reads diff and spec. Produces review notes. If critical findings, halt and prompt.
2. If all three gates pass, Documenter produces summary doc.
3. Domain doc updated if the feature added new vocabulary or shifted boundaries. For this feature: `docs/domains/library.md` gets a new section on import lifecycle.
4. Merge to `main`.
5. Branch archived (tag or delete per project convention).
6. `state.md` cleared.

**Artifacts produced:**

`docs/summaries/goodreads-import.md`:
```markdown
---
feature: goodreads-import
merged: 2026-05-26
spec: docs/specs/goodreads-import.md
plan: docs/plans/goodreads-import.md
related_adrs: [0004]
---

# Summary: Goodreads import

## What shipped
CSV-based import from Goodreads with mapping, fuzzy-author dedup, atomic
batch persistence, and a UI review-then-commit flow.

## What changed mid-feature
Spec requirement 3 amended from exact-match to normalized-match dedup
(checkpoint after step 3). Reason: real-world author name inconsistencies.

## Architectural notes
ADR-0004 confirmed: ingestion is application-layer; library domain
unchanged. The dedup module sits in domain (pure logic) and is reused
by the application service.

## Followups
- Live API import (deferred per spec non-requirements)
- Reading-progress import (separate feature)
- Periodic re-sync (separate feature)

## Security review notes
- CSV parser uses streaming; no memory exhaustion risk on large uploads
- No SQL injection risk (parameterized persistence)
- Author name normalization is unicode-aware (no homoglyph confusion)
```

`docs/domains/library.md` — appended section on import lifecycle.

`.claude/state.md` (cleared):
```markdown
# Project state

**Active feature:** none
**Active branch:** main
**Last merge:** goodreads-import (today)

## Open questions
- (none)
```

**Artifact count this phase:** 1 summary + 1 domain doc update + state.md reset = 1 new doc, 1 modified.

---

## Total artifact count across the feature

| Phase | New docs | Modified docs |
|---|---|---|
| `/feature-start` | 2 (spec, ADR) | 1 (state.md) |
| `/plan` | 1 (plan) | 1 (state.md) |
| `/build` | 0 | 1 (state.md, repeatedly) |
| `/checkpoint` | 0 | 3 (spec, plan, state.md) |
| `/feature-merge` | 1 (summary) | 2 (domain doc, state.md) |
| **Total** | **4 durable docs** | **state.md throughout** |

Four durable docs per feature (spec, plan, ADR, summary) plus targeted domain doc updates when the feature changes the domain model. That's bounded but not arbitrarily capped — exactly the shape we agreed on.

---

## What to look for in this walk-through

1. **Artifact volume.** Four durable docs per feature feels right for the engineering shape you described. If it feels light, the gap is probably in build-time documentation (e.g., should `/build` produce a build log?). If heavy, the cuttable one is most likely the ADR (only produced when architect is invoked).

2. **Checkpoint coverage.** The mid-feature checkpoint scenario is realistic — specs *do* shift mid-build. The flow handles it, but worth checking whether the spec amendment process is smooth enough or if you want a more formal "spec versioning" model.

3. **Hook silence.** The hook fired many times during `/build` but never warned, because every edit matched `owned_files`. That's the happy path. Worth thinking about: what's the user experience when the hook *does* fire? (Currently: a warning that surfaces, documenter skill or `/checkpoint` resolves.)

4. **Domain doc updates.** I had `/feature-merge` update `docs/domains/library.md`. That's a judgment call — should domain docs update automatically, or only at human request? Currently: documenter proposes, user confirms.

5. **The "no new docs during build" property.** This is deliberate. Build is execution; documents are the contract being executed against. If the contract needs to change mid-build, that's what `/checkpoint` is for.
