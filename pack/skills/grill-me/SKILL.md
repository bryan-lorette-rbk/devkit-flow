---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use during brainstorming, spec authoring, or design review; or whenever the user wants their plan stress-tested. Triggers on "grill me", "stress-test this", "interrogate the plan". Auto-invoked by `/feature-start` (brainstorm) and `/plan` (when user-facing decisions surface).
---

# Grill me

Interview the user relentlessly about every aspect of the plan or design until you reach shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

For each question, provide your recommended answer.

## How to ask

- **Walk parents before children.** A decision whose answer depends on a yet-unanswered decision is unanswerable. Pick the parent.
- **Use `AskUserQuestion` for discrete choices** (2–4 mutually-exclusive options). Don't enumerate options as prose when the tool's UI fits.
- **Batch related questions** so the user can answer a branch at once, not one question per round-trip.
- **Reflect each answer back** in one short sentence before moving to the next branch. Silent inference is the failure mode this skill prevents.

## When to stop

- The decision tree's leaves are resolved.
- The user signals "enough" ("ship it", "good enough", "stop").
- Continuing requires context the user doesn't have yet — pause, surface the partial picture, let the user fill the gap.

Stopping early because "the rest is implementation detail" is the trap. Un-grilled implementation details become bugs.

## What grilling is not

- Not adversarial. The goal is shared understanding, not debate.
- Not exhaustive enumeration. Ask the questions whose answers shape the contract; skip the ones that don't.
- Not a substitute for the `architect`. Genuinely architectural questions (bounded context, new layer, cross-cutting pattern) go to a fresh-context architect invocation — grilling the user on something they'd ratify by reflex wastes their time.
