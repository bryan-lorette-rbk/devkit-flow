---
description: Close out a feature: run three gates (tests pass → docs reconciled → security review clean) and, on success, author the summary doc, mark any superseded parked features, propose the merge mechanics, and clear `.claude/state.md`. Loads the `engineer` skill (Gate 1), the `documenter` skill (Gate 2 + summary authoring), and the `security-reviewer` subagent in fresh context (Gate 3). Halts on any gate failure; pauses for user confirmation before executing git operations.
---

Drive the three closeout gates and the merge-and-archive sequence for the active feature. One `/feature-merge` invocation completes a feature lifecycle (or halts at a gate and surfaces what blocked).

`/feature-merge` is the **gating** command, not the merge-script command. Even on the happy path, it proposes the git operations and waits for user confirmation before executing — merge is irreversible enough that explicit confirmation is the right friction.

## Arguments

`/feature-merge` takes no arguments. It operates on the active feature in `.claude/state.md`. To merge a parked feature, the user resumes it first (`/checkpoint` to update state, then `/feature-merge`).

## Preconditions

Read `.claude/state.md`. Verify:

1. `Active feature` is not `none`.
2. `Spec` points to an existing file; spec `status` is `approved` or `approved (amended ...)`.
3. `Plan` points to an existing file; plan `status` is `approved` or `approved (amended ...)`.
4. Working tree is clean (`git status` reports no uncommitted changes).
5. Current branch matches `Active branch` in state.md.

If any precondition fails, **stop and report**. Common cases:
- Dirty working tree → user commits or stashes; re-run.
- Plan still `draft` → user approves the plan (or runs `/plan` if no plan exists).
- Spec still `draft` → user approves the spec; if plan doesn't exist, run `/plan` first.

## Run

The three gates run in fixed order: tests → docs → security. Each gate's failure surfaces concrete remediation. The gates are independent — a Gate-2 failure doesn't tell you anything about Gate 3 — but they execute sequentially because each is cheap to re-run after a fix and there's no value in showing the user three problems at once.

### Gate 1 — Tests pass

Load the `engineer` skill. Identify the test runner from the plan's "Approach" section or from project config (`pyproject.toml`, `package.json`, `Cargo.toml`). Run the full test suite (not just the feature's tests — regressions matter at merge time).

- **Suite green:** proceed to Gate 2.
- **Suite red:** halt. Surface the failing tests' names and a one-line "fix or amend the plan via `/checkpoint`" prompt. Do not proceed to other gates — a red suite invalidates downstream assumptions.

Also run linter / type-checker if the project has them configured. Their failures are merge-blocking at the same severity as red tests; same halt behavior.

### Gate 2 — Docs reconciliation

Load the `documenter` skill. Run a final-pass version of Pattern D (see the documenter skill's "Pattern D — On-demand reconciliation") **plus** an additional acceptance-criteria-coverage check:

- **Pattern D checks:** `owned_files` coherence (any commits touching files outside scope?); state.md coherence (Spec/Plan paths exist; Phase makes sense for a feature about to merge); spec/plan front-matter coherence.
- **Acceptance-criteria coverage:** read the spec's "Acceptance criteria" section. For each criterion, identify which plan step (or completed work) satisfies it. Any criterion not mapped to completed work is a coverage gap. The plan's "Acceptance mapping" table (per the pm skill's plan-time guidance) is the primary source; the documenter cross-references against the plan's Completed steps in state.md.

If all checks pass: proceed to Gate 3.

If anything is unaddressed:
- **Drift surfaced:** documenter proposes resolution per Pattern A. User confirms; documenter applies; re-run Gate 2 from the top.
- **Coverage gap:** the spec promised behavior the plan/code didn't deliver. Two resolution paths:
  - **Scope-cut amendment:** trim the spec's acceptance criteria via `/checkpoint`. Honest "we shipped less than originally scoped" — explicit in the amendment note. The cut criteria become followups in the summary.
  - **Build the missing work:** continue `/build` for the remaining plan steps; come back to `/feature-merge` when complete.

The user picks. Don't proceed past Gate 2 with a coverage gap silently.

### Gate 3 — Security review

Invoke the `security-reviewer` subagent in fresh context. Pass:
- The diff command (`git diff <mainline>..HEAD`) for the subagent to run itself.
- Path to the active spec.
- Paths to related ADRs from the spec/plan front-matter.
- Path to the active plan (intent context only; not authoritative for security).

The subagent returns a structured findings document with severity-bucketed entries (critical / high / medium / low / informational).

- **Zero critical findings:** Gate 3 passes. Surface the full findings document to the user — they need to know the medium/low/informational items even though they don't block.
- **One or more critical findings:** halt. Surface the findings. User addresses (either by fixing the code, amending the spec/plan via `/checkpoint`, or — rarely — formally accepting the risk with an ADR that downgrades the finding). Re-run Gate 3 (or the full sequence from Gate 1, since fixes touch code) after resolution.

### After all three gates pass — Summary and supersede

Load the `documenter` skill again. Run the "Summary authoring" pattern (see the documenter skill):

1. Write `docs/summaries/<feature>.md` per the documenter's summary checklist. Include the security-reviewer's non-critical findings in the "Security review notes" section.
2. Update `docs/domains/<domain>.md` if the feature shifted domain vocabulary (per the documenter's "Domain doc updates" guidance). If `docs/domains/` doesn't exist and the feature is the project's first in a domain, create it.
3. **Supersede mechanic.** If the feature's spec lists `supersedes:` in its front-matter (or the work-in-progress conversation has identified parked features this merge absorbs), update `.claude/state.md`'s Parked features section: change each superseded entry's note to `superseded by <this-feature> (merged YYYY-MM-DD)`. The parked branch is **not** deleted — it remains for historical reference and possible cherry-pick — but it's clearly marked closed.

Surface all proposed doc writes to the user before applying. The documenter skill's cardinal "propose before writing" discipline holds at merge time too.

### Merge proposal

Once all docs are written, propose the merge mechanics. The pack does not assume a particular merge strategy (squash / merge commit / rebase) — it varies by project convention. Read `CLAUDE.md` for any stated preference; otherwise ask the user.

Propose, in one short message:
- The merge command (e.g., `git checkout <mainline> && git merge --no-ff feature/<slug>` for a merge commit; or `git checkout <mainline> && git merge --squash feature/<slug> && git commit` for squash).
- The post-merge cleanup (`git branch -d feature/<slug>` to delete the local branch after merge; or `git branch -m feature/<slug> archive/<slug>` to rename if the project archives rather than deletes).
- The expectation that the user reviews `git log mainline..HEAD` (or equivalent) one last time before running.

**Wait for user confirmation.** Do not execute git merge ops without explicit go-ahead. Merge is the most irreversible action in this command; the friction is intentional.

### After the merge

Once the user confirms the merge has been executed (either by them or by you on their instruction):

1. **Clear state.md** to the idle pointer shape: Active feature `none`, Active branch `<mainline>`, Phase `idle`, Spec/Plan/Next step `—`. Move the just-merged feature's entry to "Last merge: <feature> (YYYY-MM-DD)".
2. Surface a one-line completion summary (feature merged, summary doc at `<path>`, branch archived/deleted).

The pack expects the user to push the mainline branch themselves; `/feature-merge` does not auto-push (push is also irreversible from a code-review perspective).

## Halt conditions

Stop and surface, without auto-recovering:

- Any precondition fails (no active feature, dirty tree, unapproved spec/plan, wrong branch).
- Gate 1 fails (tests red or lint/typecheck fail).
- Gate 2 surfaces drift or coverage gap; user has not yet chosen a resolution path.
- Gate 3 returns one or more critical findings.
- The security-reviewer returns a finding it couldn't complete (e.g., couldn't read the diff — see the subagent's "When to return findings without completing the full review").
- The user rejects the proposed merge mechanics (e.g., the project uses a tool — `gh pr create`, `bors`, `mergify` — instead of direct `git merge`).
- The user declines to confirm the merge proposal.

After any halt, the user resolves; re-running `/feature-merge` picks up from the beginning (Gate 1). Re-running is cheap because gates 1 and 2 are mostly read-only and the security-reviewer's work is fresh-context per invocation — no harm in re-running the full sequence after a fix.

## Notes on the merge being irreversible

`/feature-merge` is the only pack command that proposes git-history-altering operations. Even though all three gates pass before the proposal, the propose-before-acting friction is deliberate. The gates catch *what we knew to check*; user review catches *what the gates didn't think to check*. Both matter.

If a merge goes wrong (e.g., the wrong branch was merged; the merge included an accidental WIP commit), revert is `git revert -m 1 <merge-commit>` for merge-commit-style merges. The pack does not include a `/feature-revert` command; that's a manual git operation by design.
