#!/usr/bin/env python3
"""install_lib.py — manifest + planning helper for the devkit installer.

Invoked by install.sh via subcommands. Each subcommand reads its args from
sys.argv and prints structured output to stdout (machine-parseable lines)
plus human-readable messages to stderr. Bash interprets stdout.

Subcommands:

  manifest-read MANIFEST_PATH
    Prints: VERSION\\n on success, empty on missing/malformed.

  plan PACK_DIR TARGET_DIR MANIFEST_PATH PACK_VERSION
    Compares pack/ on disk to manifest stored at MANIFEST_PATH; prints a plan
    line per file:
      UPDATE   <rel-path>      (file exists, hash matches manifest)
      SKIP     <rel-path>      (file exists, hash does NOT match manifest — user customized)
      NEW      <rel-path>      (file does not exist in target)
      UNCHANGED <rel-path>     (file exists, hash already matches pack's hash — no-op)
    After file lines, prints:
      TEMPLATE-CHANGED <name>  (if a template's hash differs from manifest)
      TEMPLATE-UNCHANGED <name>
    Exits 0 always (plan is informational).

  manifest-write PACK_DIR TARGET_DIR MANIFEST_PATH PACK_VERSION
    Walks pack/ files, computes hashes from the files now in TARGET/.claude/,
    writes manifest JSON. Used after install/update completes.

All paths are absolute. PACK_DIR is the path to the pack/ directory (not its
parent). TARGET_DIR is the project root being installed into. MANIFEST_PATH
is the absolute path to TARGET/.claude/.devkit-manifest.json.
"""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


# --- File mapping --------------------------------------------------------------
# Each entry: (path-under-pack/, path-under-target/). Pack files that map to
# .claude/ tracked locations.
TRACKED_DIRS = ("skills", "agents", "commands", "hooks")
EXCLUDED_PACK_FILES = ("hooks/settings.json.fragment",)


def iter_tracked_pack_files(pack_dir: Path):
    """Yield (pack_rel, target_rel) pairs for every tracked pack file."""
    for top in TRACKED_DIRS:
        src_top = pack_dir / top
        if not src_top.is_dir():
            continue
        for path in sorted(src_top.rglob("*")):
            if not path.is_file():
                continue
            pack_rel = path.relative_to(pack_dir).as_posix()
            if pack_rel in EXCLUDED_PACK_FILES:
                continue
            target_rel = f".claude/{pack_rel}"
            yield (pack_rel, target_rel)


TEMPLATE_FILES = (
    ("CLAUDE.md.template", "CLAUDE.md.template"),
    ("state.md.template", "state.md.template"),
)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_manifest(manifest_path: Path) -> dict | None:
    if not manifest_path.is_file():
        return None
    try:
        return json.loads(manifest_path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


# --- Subcommand: manifest-read -------------------------------------------------
def cmd_manifest_read(args: list[str]) -> int:
    (manifest_path,) = args
    data = read_manifest(Path(manifest_path))
    if data and isinstance(data.get("devkit_version"), str):
        print(data["devkit_version"])
    return 0


# --- Subcommand: plan ----------------------------------------------------------
def cmd_plan(args: list[str]) -> int:
    pack_dir_s, target_dir_s, manifest_path_s, pack_version = args
    pack_dir = Path(pack_dir_s)
    target_dir = Path(target_dir_s)
    manifest_path = Path(manifest_path_s)

    manifest = read_manifest(manifest_path) or {}
    tracked_old: dict[str, str] = manifest.get("tracked", {})
    templates_old: dict[str, str] = manifest.get("templates", {})

    # File plan
    for pack_rel, target_rel in iter_tracked_pack_files(pack_dir):
        pack_file = pack_dir / pack_rel
        target_file = target_dir / target_rel
        new_hash = sha256_file(pack_file)
        if not target_file.exists():
            print(f"NEW {target_rel}")
            continue
        current_hash = sha256_file(target_file)
        if current_hash == new_hash:
            print(f"UNCHANGED {target_rel}")
            continue
        manifest_hash = tracked_old.get(target_rel)
        if manifest_hash is None:
            # File exists but wasn't in manifest — treat as customized (we can't
            # prove the user didn't create it on purpose).
            print(f"SKIP {target_rel}")
        elif current_hash == manifest_hash:
            # File matches what we installed; safe to update to new version.
            print(f"UPDATE {target_rel}")
        else:
            # File differs from both new pack AND manifest — user modified it.
            print(f"SKIP {target_rel}")

    # Template plan — never auto-applied, only surfaced as advisory.
    for pack_rel, _ in TEMPLATE_FILES:
        pack_file = pack_dir / pack_rel
        if not pack_file.is_file():
            continue
        new_hash = sha256_file(pack_file)
        old_hash = templates_old.get(pack_rel)
        if old_hash is None or old_hash != new_hash:
            print(f"TEMPLATE-CHANGED {pack_rel}")
        else:
            print(f"TEMPLATE-UNCHANGED {pack_rel}")

    return 0


# --- Subcommand: manifest-write ------------------------------------------------
# The manifest entry for a tracked file records "what hash did *we* install for
# this path?" so a future plan can tell user-customization from a clean install.
# Rules:
#   - If target file's current hash == pack file's hash → record pack hash
#     (we agree; this is the install we own).
#   - Otherwise → preserve the prior manifest entry if it exists; omit if not.
#     (User has customized; we did NOT install this content, so we must not
#     claim to have installed it — that would silently bless the customization
#     and cause the next update to overwrite without a SKIP warning.)
def cmd_manifest_write(args: list[str]) -> int:
    pack_dir_s, target_dir_s, manifest_path_s, pack_version = args
    pack_dir = Path(pack_dir_s)
    target_dir = Path(target_dir_s)
    manifest_path = Path(manifest_path_s)

    prior = read_manifest(manifest_path) or {}
    prior_tracked: dict[str, str] = prior.get("tracked", {})
    prior_templates: dict[str, str] = prior.get("templates", {})

    tracked = {}
    for pack_rel, target_rel in iter_tracked_pack_files(pack_dir):
        pack_file = pack_dir / pack_rel
        target_file = target_dir / target_rel
        pack_hash = sha256_file(pack_file)
        if target_file.is_file():
            target_hash = sha256_file(target_file)
            if target_hash == pack_hash:
                tracked[target_rel] = pack_hash
            elif target_rel in prior_tracked:
                tracked[target_rel] = prior_tracked[target_rel]
            # else: target exists but neither matches pack nor has prior entry;
            # omit so the next plan correctly flags it as SKIP.

    # Templates are advisory — always record the current pack template hash so
    # the next install can detect changes between installed and current.
    templates = {}
    for pack_rel, _ in TEMPLATE_FILES:
        pack_file = pack_dir / pack_rel
        if pack_file.is_file():
            templates[pack_rel] = sha256_file(pack_file)
        elif pack_rel in prior_templates:
            templates[pack_rel] = prior_templates[pack_rel]

    manifest = {
        "devkit_version": pack_version,
        "installed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tracked": tracked,
        "templates": templates,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


# --- Dispatch ------------------------------------------------------------------
DISPATCH = {
    "manifest-read": cmd_manifest_read,
    "plan": cmd_plan,
    "manifest-write": cmd_manifest_write,
}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: install_lib.py <subcommand> [args...]", file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd not in DISPATCH:
        print(f"unknown subcommand: {cmd}", file=sys.stderr)
        return 2
    try:
        return DISPATCH[cmd](argv[2:])
    except TypeError as exc:
        print(f"bad arg count for {cmd}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
