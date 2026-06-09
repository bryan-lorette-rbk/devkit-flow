# Framework Comparison: Requirements × Approaches

**Purpose:** Audit the claim that the proposed compositional skill-pack actually beats the alternatives for this user's engineering shape. If any row shows an alternative meeting requirements as well or better at lower cost, the synthesis is suspect.

**Scoring:**

- ✅ Strong native support — designed for this
- 🟡 Partial — possible but not first-class, or requires user discipline to maintain
- ⚠️ Weak — present in name only, or fights the framework's grain
- ❌ Absent — not addressed; would have to be added

**Scoring is for the framework as-shipped**, not "what you could bolt on." Bolt-ons are what we're trying to avoid.

---

## Requirements matrix

| Requirement | Superpowers | GSD | SpecKit | BMAD | Proposed Pack |
|---|---|---|---|---|---|
| **Domain breakdown** of large features | ⚠️ Task-local; no domain layer | 🟡 Light decomposition in planning | ✅ Strong spec decomposition | ✅ Multi-agent decomposition | ✅ PM skill + `/feature-start` |
| **Spec-first** discipline | ✅ Plans (== specs) are required before code | 🟡 Plans exist; specs implicit | ✅ Specs are central | ✅ Specs are central | ✅ `/plan` blocks without approved spec |
| **Brainstorm-to-spec** flow | ✅ Plans == specs; brainstorm-to-plan is core | 🟡 Ad-hoc | 🟡 Templated but rigid | 🟡 Persona-driven, verbose | ✅ PM skill owns pattern; architect subagent for design Qs |
| **Implementation plan** as discrete artifact | ✅ Plans are core | ✅ Plans are core | ✅ | ✅ | ✅ `docs/plans/<feature>.md` |
| **Branch-per-feature** loop | 🟡 Possible, not enforced | ✅ Core loop | ⚠️ Branch-agnostic | ⚠️ Branch-agnostic | ✅ `/feature-start` + `/feature-merge` |
| **TDD enforced** structurally | ✅ Tester subagent, red-green-refactor | 🟡 Encouraged | ⚠️ Mentioned, not enforced | 🟡 Tester persona, verbose | ✅ Tester subagent + engineer skill |
| **SOLID enforced** | 🟡 Implicit in code review | ❌ | ❌ | 🟡 Architect persona | ✅ Engineer skill checklist on every diff |
| **Clean Architecture** layering | ❌ | ❌ | ⚠️ Mentioned | 🟡 Architect persona | ✅ Engineer skill rules + architect subagent for ambiguous boundaries |
| **Living docs** — specs always current | ⚠️ Thin docs; no currency mechanism | 🟡 User discipline | 🟡 Spec is canonical but no currency enforcement | 🟡 Heavy docs; currency by ceremony | ✅ Three-layer enforcement (hook + skill + merge gate) |
| **Living docs** — ADRs | ❌ | ❌ | 🟡 Optional | ✅ Standard artifact | ✅ Architect subagent auto-produces on non-trivial decisions |
| **Living docs** — summaries / retrospectives | ❌ | ⚠️ Manual | 🟡 End-of-phase docs | ✅ Standard artifact | ✅ Documenter skill at `/feature-merge` |
| **Project-scope memory** (not just current task) | ❌ Primary weakness | ⚠️ User-maintained | 🟡 Spec serves as memory | ✅ Heavy doc tree | ✅ Hybrid memory layout (`docs/` + `.claude/state.md`) |
| **Lean persona count** | ✅ Tester, reviewer | ✅ Minimal | 🟡 Several roles | ⚠️ Many agents, heavy orchestration | ✅ 3 agents + 3 skills based on isolation need |
| **Native Claude Code primitives** | ✅ Uses subagents, skills | ✅ Uses commands, skills | ⚠️ Parallel framework | ❌ Parallel framework | ✅ Native-first by design |
| **Artifact volume per feature** | ✅ Low | ✅ Low | 🟡 Medium | ⚠️ High | ✅ Bounded but not arbitrarily capped (spec, plan, ADRs as needed, summary) |
| **Phase count per feature** | ✅ Few | ✅ Few | 🟡 Several | ⚠️ Many gates | ✅ 5 commands map to 5 phases |
| **Karpathy-style** (small reversible steps, verify-as-you-go) | ✅ Core discipline | 🟡 Implicit | ⚠️ Big-batch spec-then-build | ⚠️ Big-batch phase gates | ✅ Engineer skill encodes explicitly |
| **Memory-palace** (location-addressable context) | ❌ Flat task focus | ⚠️ User-maintained | 🟡 Spec tree | ✅ Doc tree, heavy | ✅ Hybrid layout: durable rooms + working pointer |
| **Small-team fit** (not enterprise ceremony) | ✅ | ✅ | 🟡 | ⚠️ Enterprise-shaped | ✅ Designed for small team |
| **Security review** as discrete step | ❌ | ❌ | 🟡 Optional | ✅ Security persona | ✅ Security-reviewer subagent at `/feature-merge` |

---

## Score summary

| Framework | ✅ | 🟡 | ⚠️ | ❌ |
|---|---|---|---|---|
| Superpowers | 8 | 4 | 2 | 6 |
| GSD | 4 | 9 | 3 | 4 |
| SpecKit | 5 | 9 | 5 | 1 |
| BMAD | 8 | 6 | 6 | 0 |
| **Proposed Pack** | **20** | **0** | **0** | **0** |

The proposed pack hitting all ✅ is expected — it was designed against this requirement list. **The point of the table isn't to celebrate the pack's score; it's to show *where* each alternative falls short, and confirm the gaps line up with the gaps you named.**

---

## Reading the table — what it tells us

**Superpowers' profile** (8 ✅ / 6 ❌) — bimodal. Strong where it tries (TDD, native primitives, lean personas, Karpathy-style, and — once you read Plans as Specs — spec-first and brainstorm-to-spec). Absent everywhere project-scope matters (domain breakdown, ADRs, summaries, project memory, Clean Architecture, security). Confirms your read: excellent at the current feature, blind to the project around it.

**GSD's profile** (4 ✅ / 9 🟡) — lots of yellows. Mostly "user discipline can fill this in." That's lighter weight by virtue of leaving requirements to the human. Fine for some teams; not what you want when the goal is the *system* enforcing the shape.

**SpecKit's profile** (5 ✅ / 9 🟡) — also mostly yellows, but for a different reason: templates and structure exist, currency and enforcement don't. Spec-first is real; spec-staying-current is aspirational.

**BMAD's profile** (8 ✅ / 6 ⚠️) — the most ✅s of any alternative, but six ⚠️s clustered on weight (phases, artifacts, orchestration, enterprise shape, branch-agnostic, big-batch). Confirms your read: it does the things, but the cost is too high for a small team using native tooling.

**Where the proposed pack earns its keep:**

- ✅ on "living docs / specs current" — *only* framework with structural currency enforcement (three-layer defense)
- ✅ on "project-scope memory" — addresses Superpowers' primary weakness directly
- ✅ on "domain breakdown" + "Clean Architecture" + "SOLID" — fills the project-scope and engineering-discipline gaps Superpowers leaves open
- ✅ on "ADRs" + "summaries" + "security review" — BMAD has these but at the cost of weight; the pack keeps them as bounded artifacts
- ✅ on "native primitives" + ✅ on "lean persona count" — matches Superpowers/GSD here while keeping BMAD's role coverage

The honest summary: **Superpowers gets more right than the original scoring suggested**, and the pack's value over Superpowers is concentrated specifically in (a) project-scope memory, (b) domain breakdown, (c) doc currency, and (d) Clean Architecture / SOLID enforcement. That's a narrower delta than the raw score difference implies — but it's also exactly the delta you named at the start.

---

## Honest caveats

A few things this table understates that are worth naming:

1. **The proposed pack is unbuilt.** Every other framework has been used by real people on real projects. The pack is a design. Its scores are predictions, not measurements. Slice 1 of the build order exists specifically to validate the TDD slice on a real feature before the whole pack is committed.

2. **BMAD's heaviness isn't always wrong.** For larger teams or higher-stakes work, the ceremony pays for itself. The judgment "too heavy" is contextual to small-team, native-tooling, fast-iteration work — which is your context.

3. **GSD's yellows aren't failures.** A framework that leaves requirements to user discipline is making a deliberate trade. We're choosing differently because you specifically said you want the structure enforced, not encouraged.

4. **Some ✅s in the pack column depend on the documenter skill and hook working well in practice.** The three-layer doc-currency defense is the most novel part of the design and the most likely to need refinement once we have real usage.

---

## Conclusion

The synthesis claim survives the audit: each alternative has a specific shape that misses your requirements in a specific way, and the proposed composition picks up the pieces each one drops without inheriting another's weight. The pack's design is justified — but unproven, which is what the build-order's "dogfood after slice 1" discipline is for.
