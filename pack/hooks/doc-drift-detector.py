#!/usr/bin/env python3
"""doc-drift-detector — devkit pack PostToolUse hook.

Reads `.claude/state.md` to find the active feature's spec; reads the
spec's front-matter `owned_files` globs; checks the file path that the
preceding Edit/Write tool call touched. If the path matches no glob, prints
a warning to stderr (which the Claude Code harness surfaces back to the
model). Never blocks; always exits 0.

Design constraints (from devkit ADR-0001 + slice-5 design):
  - Does not auto-edit any document.
  - Does not block tool execution.
  - Silent when no drift is detected (no noise on the happy path).
  - Survives malformed inputs gracefully; never crashes the harness.

Install: registered as a `PostToolUse` matcher for `Edit | Write |
NotebookEdit | MultiEdit` in `.claude/settings.json`. See
`pack/hooks/settings.json.fragment` for the snippet.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Built-in path exclusions — project-meta paths that are NEVER feature-scoped.
# Editing these never indicates drift; the documenter skill amends them
# routinely. Keep this list narrow; expand only with evidence.
EXCLUDED_PREFIXES: tuple[str, ...] = (
    ".claude/",          # pack install + state
    "docs/",             # specs, plans, ADRs, summaries, domains, authoring notes
    "CLAUDE.md",
    "README.md",
    ".gitignore",
    "pyproject.toml",    # config; cross-cutting (when chungar adds tools, etc.)
    "package.json",      # same, for Node projects
    "Cargo.toml",        # same, for Rust
)

# Tool names that touch files. The settings.json matcher should also
# filter these, but defense in depth.
EDIT_TOOLS: frozenset[str] = frozenset({"Edit", "Write", "NotebookEdit", "MultiEdit"})


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        # Never crash on malformed input — the harness's contract isn't ours to police.
        return 0

    tool_name = payload.get("tool_name", "")
    if tool_name not in EDIT_TOOLS:
        return 0

    tool_input = payload.get("tool_input") or {}
    edited_path = _extract_edited_path(tool_input)
    if not edited_path:
        return 0

    cwd_str = payload.get("cwd") or "."
    project_root = Path(cwd_str).resolve()

    # Make path project-relative; bail if it lives outside the project.
    try:
        rel_path = Path(edited_path).resolve().relative_to(project_root)
    except (ValueError, OSError):
        return 0

    rel_path_str = rel_path.as_posix()

    # Built-in exclusions: never flag project-meta paths.
    if _is_excluded(rel_path_str):
        return 0

    state_md = project_root / ".claude" / "state.md"
    if not state_md.exists():
        return 0  # no devkit state — hook is a no-op

    try:
        state_text = state_md.read_text(encoding="utf-8")
    except OSError:
        return 0

    active_feature = _extract_state_field(state_text, "Active feature")
    if not active_feature or active_feature.lower() == "none":
        return 0  # nothing active; no scope to check against

    spec_field = _extract_state_field(state_text, "Spec")
    if not spec_field or spec_field == "—":
        return 0

    # Strip parenthetical annotations: "docs/specs/foo.md (approved; amended ...)"
    spec_rel = spec_field.split("(", 1)[0].strip()
    if not spec_rel:
        return 0

    spec_path = (project_root / spec_rel).resolve()
    if not spec_path.exists():
        return 0

    try:
        spec_text = spec_path.read_text(encoding="utf-8")
    except OSError:
        return 0

    owned_globs = _extract_owned_files(spec_text)
    if not owned_globs:
        return 0  # no scope declared; can't detect drift

    if any(_glob_matches(rel_path_str, g) for g in owned_globs):
        return 0  # in-scope edit; nothing to surface

    # Out of scope — surface a warning. Stderr is what the harness shows
    # to the model as additional context after the tool runs.
    print(
        f"devkit drift-detector: edit touched `{rel_path_str}`, which isn't "
        f"covered by any glob in `{spec_rel}`'s `owned_files` front-matter "
        f"(active feature: {active_feature}). Either expand the spec's scope "
        f"via `/checkpoint <description>` or move this change to a different "
        f"feature. (The hook does not block; this is informational.)",
        file=sys.stderr,
    )
    return 0


def _extract_edited_path(tool_input: dict) -> str:
    """Extract the file path the tool touched.

    Tool input schemas:
      Edit: {"file_path": "..."}
      Write: {"file_path": "...", "content": "..."}
      NotebookEdit: {"notebook_path": "...", ...}
      MultiEdit: {"file_path": "...", "edits": [...]}
    """
    for key in ("file_path", "notebook_path", "path"):
        v = tool_input.get(key)
        if isinstance(v, str) and v:
            return v
    return ""


def _is_excluded(rel_path: str) -> bool:
    for prefix in EXCLUDED_PREFIXES:
        if rel_path == prefix or rel_path.startswith(prefix):
            return True
    return False


def _extract_state_field(state_text: str, field: str) -> str:
    """Read a `**Field:** value` line from state.md."""
    pattern = re.compile(rf"^\*\*{re.escape(field)}:\*\*\s*(.+?)\s*$", re.MULTILINE)
    m = pattern.search(state_text)
    return m.group(1).strip() if m else ""


def _extract_owned_files(spec_text: str) -> list[str]:
    """Read the `owned_files:` list from spec front-matter.

    Front-matter is delimited by `---` lines at the top of the file.
    `owned_files` is a YAML list of glob strings:

        owned_files:
          - src/foo/**
          - tests/foo/**

    We parse only what we need — no PyYAML dependency.
    """
    fm = _extract_front_matter(spec_text)
    if not fm:
        return []

    in_owned = False
    globs: list[str] = []
    for raw_line in fm.splitlines():
        line = raw_line.rstrip()
        if not line:
            continue
        # Top-level key (no leading whitespace, ends with ":")
        if re.match(r"^[a-zA-Z_][\w-]*:\s*$", line):
            in_owned = line.startswith("owned_files:")
            continue
        if re.match(r"^[a-zA-Z_][\w-]*:", line):
            in_owned = False
            continue
        if in_owned:
            # list item: "  - <glob>"
            m = re.match(r"^\s*-\s*['\"]?(.+?)['\"]?\s*$", line)
            if m:
                glob = m.group(1).strip()
                # Strip leading "./" if present
                glob = glob.removeprefix("./")
                globs.append(glob)
    return globs


def _extract_front_matter(text: str) -> str:
    """Extract YAML front-matter between leading `---` fences. Empty string if absent."""
    if not text.startswith("---"):
        return ""
    # Find the closing fence
    rest = text[3:]
    # Skip an optional newline immediately after opening fence
    if rest.startswith("\n"):
        rest = rest[1:]
    close = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not close:
        return ""
    return rest[: close.start()]


def _glob_matches(path: str, glob: str) -> bool:
    """Match path against a glob with `**` (any depth) and `*` (within segment) support.

    Globs follow common conventions:
      - `src/**`           — any file under src/, any depth
      - `src/foo/*.py`     — direct children of src/foo/ matching *.py
      - `src/foo/**/*.py`  — any .py under src/foo/, any depth
      - `chungar/agent.py` — exact path
    """
    regex = _glob_to_regex(glob)
    return bool(regex.match(path))


def _glob_to_regex(glob: str) -> re.Pattern[str]:
    """Translate a path glob into an anchored regex pattern."""
    out: list[str] = []
    i = 0
    while i < len(glob):
        c = glob[i]
        if c == "*":
            # Look ahead for "**"
            if i + 1 < len(glob) and glob[i + 1] == "*":
                # ** — matches any number of path segments (including zero)
                # Consume optional trailing "/"
                j = i + 2
                if j < len(glob) and glob[j] == "/":
                    # "**/" — matches zero-or-more segments followed by /
                    out.append("(?:.*/)?")
                    i = j + 1
                    continue
                # Trailing ** with no slash: matches everything from here
                out.append(".*")
                i = j
                continue
            # Single * — matches any chars except /
            out.append("[^/]*")
            i += 1
            continue
        if c == "?":
            out.append("[^/]")
            i += 1
            continue
        if c in r".+()[]{}|^$\\":
            out.append("\\" + c)
            i += 1
            continue
        out.append(c)
        i += 1
    return re.compile(f"^{''.join(out)}$")


if __name__ == "__main__":
    sys.exit(main())
