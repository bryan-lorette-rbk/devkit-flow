# Clean Architecture layering

Used by: `engineer` skill (Refactor step + plan-time step ordering), `architect` agent.

Layers, innermost to outermost:

1. **Domain** — pure business logic, entities, value objects. No I/O. No framework imports. No knowledge of databases, HTTP, files, time, randomness.
2. **Application** — use cases, services that orchestrate domain objects. Defines *ports* (interfaces) for what it needs from the outside world.
3. **Adapters** — implementations of those ports. Translate between the application's port interface and a specific external system (sqlite repo, HTTP client, file reader, agent runtime tool).
4. **Infrastructure / framework** — wiring, dependency injection, framework entry points (CLI, web server, agent runtime).

**The dependency rule, non-negotiable:** code in an inner layer must not depend on code in an outer layer. Domain knows nothing about application. Application knows nothing about adapters. Adapters know nothing about framework wiring.

In practice:

- A domain class never imports from `adapters/`, `infrastructure/`, or any third-party I/O library.
- An application service depends on a port interface declared in the application layer, not on the concrete adapter.
- An adapter depends on the port it implements and on the third-party library it wraps.
- Framework wiring composes everything; nothing imports from framework wiring.

**Plan-time step ordering.** Steps go innermost layer first, outward — pure domain → application services with ports → adapters → wiring / framework / entry-point. A step may depend on code from earlier steps; never on code from later steps. This is what lets each step's tests run *without* the later layers existing, which is what makes each step independently revertable. (The engineer skill's plan-time section explains the test-revertability rationale; this reference is the layer definition only.)

When unsure which layer a piece of code belongs in, or whether a new module justifies a new layer, invoke the `architect` subagent in fresh context with the design question. Do not guess on architectural boundaries; the cost of getting it wrong propagates.
