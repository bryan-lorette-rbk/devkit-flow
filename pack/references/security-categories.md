# Security review categories

Used by: `security-reviewer` agent (per-hunk review).

For each category, name *what would have to be true* for the code to be vulnerable. If the spec or observed behavior rule that out, say so explicitly; otherwise flag.

- **Injection.** SQL, shell, command, NoSQL, LDAP, XPath, template injection. Look for: string concatenation into queries, `os.system` / `subprocess` with user input, `eval` / `exec`, template engines fed unescaped input. Confirmed-safe patterns: parameterized queries (`?` placeholders, prepared statements), `subprocess` with array args + `shell=False`.
- **Secrets and credentials.** Hardcoded API keys, passwords, tokens; secrets in logs or error messages; secrets in version control. Check: any string literal that looks like a key (long base64-ish, `sk-...`, `AKIA...`, etc.); any `print` / `log` of an object that might include credentials.
- **Unsafe deserialization.** `pickle.loads`, `yaml.load` (vs `yaml.safe_load`), `marshal.loads`, JSON deserialization into types that execute on construction. Pydantic-based deserialization is generally safe (no code execution) unless `__init_subclass__` magic is in play.
- **Path traversal.** User input flowing into file paths without normalization. Check: any `open(user_input)` or `Path(user_input)` where `user_input` could contain `..` or absolute paths. Safe pattern: `Path(user_input).resolve().relative_to(allowed_root)` with a try/except.
- **Cryptography.** Hand-rolled crypto, weak algorithms (MD5/SHA1 for security, DES, RC4), hardcoded IVs / nonces, missing authentication on encrypted data, predictable randomness (`random` vs `secrets`). For most internal features, "no crypto" is the right answer; only flag when crypto is actually present.
- **Authentication and authorization.** Missing checks; checks at the wrong layer (UI but not API); checks that can be bypassed by direct calls; trust of client-supplied identity claims; session handling. Match scope to what the spec describes — personal-scale local features may legitimately have no auth surface.
- **Input validation.** Type confusion, missing length / range / format checks, type coercion surprises. Pydantic-validated boundaries are usually fine; non-validated I/O entry points (raw HTTP body, raw CLI input, raw file content) need explicit checks.
- **Output encoding.** XSS in HTML, log injection (newlines in user input), CSV injection (`=`, `+`, `-`, `@` prefixes in CSV cells), HTTP header injection. Match to output channel: if the feature only emits structured JSON to internal callers, most of these don't apply.
- **Denial of service.** Unbounded allocations (reading entire user-supplied file into memory; unbounded loop driven by user input); regex catastrophic backtracking; recursion bombs; rate-unbounded expensive operations. Severity depends on the threat model — internal CLI tools are usually lower-severity than public endpoints.
- **Concurrency hazards.** TOCTOU on file operations; race conditions in shared state; transaction boundaries that don't actually isolate. Often surfaces in features that introduce caching, lock files, or database transactions.
- **Dependency hygiene.** New dependencies introduced in `pyproject.toml` / `package.json` / etc. — known-vulnerable versions, abandoned packages, typosquatted names. Flag added deps for the user to verify against their dep-vetting process; you don't need to actually fetch CVE feeds, but you should name the deps.
- **Logging and observability of sensitive data.** Logging request bodies that may contain PII / secrets; structured logging fields that include credentials.
- **Error-handling information leaks.** Stack traces or detailed error messages returned to untrusted callers. Internal services may legitimately surface stack traces; user-facing endpoints should not.

If a category genuinely doesn't apply because of the feature's shape (e.g., "no user-facing output; no XSS surface"), say so once and move on. Boilerplate "category doesn't apply" lines for every category produce noise; group them.
