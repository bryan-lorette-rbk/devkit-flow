# SOLID checklist

Used by: `engineer` skill (Refactor step + plan-time review), `architect` agent (when invoked for layering questions).

Apply these as **questions you ask of a diff**, not as gates that fire automatically. "This principle doesn't apply here" is a valid answer — but you should be able to say it explicitly. Per-diff, not per-codebase: you are not re-auditing the whole project, you are checking that the changes you just made don't introduce a violation.

- **Single Responsibility.** Does this module have one reason to change? If a change to persistence and a change to validation both modify the same file, the file is doing two jobs.
- **Open/Closed.** Could a future variant be added by extension (new file, new implementation of an existing interface) rather than modification (editing this file)? If every new case requires editing the same switch statement, the design is closed against the wrong axis.
- **Liskov Substitution.** If this is a subtype or implementation of an interface, can it be used wherever the interface is expected without surprising the caller? Throwing `NotImplementedError` from a method the interface promises is a Liskov violation.
- **Interface Segregation.** Are clients forced to depend on methods they don't use? A fat interface that 80% of clients only use 20% of is asking to be split.
- **Dependency Inversion.** Does this code depend on a concrete class it could depend on an interface for? A direct import of a database driver from a domain module is the canonical violation.
