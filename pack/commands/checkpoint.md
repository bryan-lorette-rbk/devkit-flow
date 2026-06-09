---
description: Mid-feature doc-sync and amendment. Loads the `documenter` skill to propose (never silently apply) changes to specs, plans, ADRs, summaries, domain docs, and `.claude/state.md`. Three modes: with a description (amend), with `park` (park the feature), or with no args (interactive: ask what changed, or run a lightweight drift-reconciliation pass).
---

Drive the `documenter` skill to keep durable docs current with reality. One `/checkpoint` invocation handles one amendment (or one park, or one reconciliation pass). The skill governs the cardinal discipline (propose before writing); this command sequences phases and handles side-effects.

## Arguments

`/checkpoint <text>` accepts free-form text describing what changed or what to amend. Three recognized shapes:

- **`/checkpoint <description>`** — amendment mode. The description is the change the user wants made (e.g., `/checkpoint dedup needs fuzzy author matching, exports have inconsistent spacing`). Routes to documenter's Pattern A.
- **`/checkpoint park`** — park transition. Clears state.md's Active feature into the "Parked features" section without merging. Routes to documenter's Pattern C. Optional trailing text becomes the Parked-features entry's reason note (`/checkpoint park waiting on legal review of CSV terms`).
- **`/checkpoint`** (no args) — interactive mode. Ask the user "what changed?" If they describe a change, route to Pattern A. If they ask for a drift check or say "nothing in particular, just want to audit," run the lightweight reconciliation pass (Pattern D). If they answer with `park`, route to Pattern C.

Argument shape is heuristic; if ambiguous, ask the user before assuming.

## Preconditions

1. Read `.claude/state.md`.
2. Verify: `Active feature` is not `none`. If there is no active feature, surface that and stop — there's nothing to checkpoint against. (Exception: a no-args invocation can still propose to amend `CLAUDE.md` or the memory layout itself, but that's an unusual case; confirm with the user before proceeding.)
3. Working tree may have uncommitted changes; `/checkpoint` reads the diff to inform the proposal but does not stage or commit anything itself. Amendment commits are a separate user action after the documenter applies edits.

If preconditions pass, load the `documenter` skill and proceed to the right phase based on argument shape.

## Run

The phases below mirror the documenter skill's amendment loop. The skill is the source of truth for *how*; this command is the source of truth for *when state.md gets touched and when the user is asked to confirm*.

### Phase A — Orient

Read, in this order:

- `.claude/state.md` (already read for preconditions).
- The active spec (path from state.md).
- The active plan if it exists.
- Any ADRs named in spec/plan front-matter `related_adrs`.
- The feature branch's commit log since divergence from mainline (`git log mainline..HEAD --oneline`) and the diff (`git diff mainline..HEAD --stat`) to ground the reconciliation in actual code changes. Skip if the working tree is clean and the branch is at the mainline tip (rare in practice).

If the active feature's spec or plan can't be read, surface that and stop — checkpoint can't propose amendments against missing docs.

### Phase B — Identify scope

Based on arguments:

- **Amendment mode (Pattern A):** Restate the user's described change in one sentence. Confirm the restatement matches intent. If the change touches concepts outside the spec's current scope, flag it and ask whether to amend in place or escalate (see documenter's "When to escalate").

- **Park mode (Pattern C):** Confirm the user wants to park (one quick confirmation — park is reversible but mildly annoying to undo, so explicit confirmation is cheap insurance). Capture the optional reason note.

- **No-args mode:** Ask the user "what changed?" with three options: describe a specific amendment, request a drift-reconciliation pass, or park. Route based on answer.

### Phase C — Propose

Per the documenter skill's "Propose before writing. Always." discipline:

- For amendment-mode and spec-gap (Pattern B, often invoked here via plan-time work): identify affected docs per the documenter skill's "What lives where" table. Produce a proposal that names each affected file and the specific edits (line-level diff for small, section-level summary for large). Include any required `status` lifecycle updates per the "Status and lifecycle handling" rules.

- For park-mode: produce the state.md edit (Active feature → none; Phase → idle; Spec/Plan/Next step → —; append Parked features entry with branch name, last completed step, optional reason). Show the edit.

- For no-args reconciliation: run the lightweight drift checks (owned_files coherence, state.md coherence, front-matter coherence). Surface findings; if drift is found, propose targeted fixes. If clean, say so explicitly and exit Phase C without a proposal.

Surface the proposal to the user. Wait for confirmation.

### Phase D — Apply

Once the user confirms, apply only the confirmed edits. If the user revised the proposal, apply the revised version, not the original. Do not "iterate" by applying a first version and refining — re-propose first, apply once.

After applying:
- Routine state.md fields (`Phase`, `Next step`) get updated without further confirmation.
- Substantive state.md changes (Active feature clear, Parked features entry, Open questions add) are part of the proposal and were already confirmed.

### Phase E — Hand off

Pause for the user. Surface, in one short message:

- One line per file amended (path + summary of change).
- For park mode: one line confirming the feature is parked and naming the branch that remains.
- For no-args mode with no drift: one line "no drift detected."

Propose a commit for the amendment before exiting — same shape as the engineer skill's commit substep. Subject names the amendment pattern (e.g., `/checkpoint A: <description>`, `/checkpoint B: <spec gap>`, `/checkpoint C: park <slug>`, `/checkpoint D: <drift resolution>`). Body: one paragraph naming the docs touched and what was changed. Stage only the files the documenter actually amended (typically spec + plan + state.md; for ADR work, the ADR + spec front-matter `related_adrs`). Never `git add -A`.

Wait for user confirmation. On decline, leave the proposal visible and exit without committing — the amendment may need further iteration, may batch with other in-flight work, or may belong in a different shape. The propose-then-easy-decline pattern preserves the user's right to defer while ending the silent-omission failure mode the older "do not commit" wording produced.

## Halt conditions

Stop and surface to the user (do not auto-recover) if:

- Preconditions fail (no active feature in state.md and the request requires one).
- The active spec or plan can't be read.
- The amendment scope is unclear and the user can't disambiguate.
- The user proposes an amendment that would violate an accepted ADR; surface the conflict and recommend either superseding the ADR or revising the amendment.
- The amendment is so substantial it's effectively a new feature; recommend `/feature-start <new-name>` with the current feature parked.
- The reconciliation pass surfaces drift the user doesn't immediately want to address — record under state.md's Open questions and exit without amending. Open questions are the right home for "we know this is drifting; we'll deal with it next slice."
- The proposed commit cannot be staged (e.g., the documenter expected a file that isn't on disk, or `git add` errors out). Surface; do not work around it.

The documenter skill's "When to stop and ask the user" section names additional cases. Defer to the skill on judgment calls about whether to ask vs proceed.

## Notes on overlap with the drift-detection hook

The slice-5 drift-detection hook (when shipped) fires on `PostToolUse` and surfaces drift warnings the user must address. `/checkpoint` no-args is the manual equivalent — same checks, on-demand rather than reactive. Both layers complement: the hook catches drift at the moment of edit (cheap to fix immediately); `/checkpoint` catches accumulated drift the user wants to audit deliberately.

When the hook lands, this command's no-args reconciliation pass may become redundant for most cases — but the manual trigger is still valuable for "I want to audit before committing a batch" workflows. Don't deprecate; revisit after the hook has usage data.
