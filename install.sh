#!/usr/bin/env bash
# install.sh — install the devkit Claude Code skill-pack into a target project.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--project-name NAME] [--description TEXT] [--mainline BRANCH]
#
# TARGET_DIR defaults to the current directory.
# --project-name fills the {{PROJECT_NAME}} slot in CLAUDE.md (default: basename
#   of TARGET_DIR).
# --description fills the {{ONE_LINE_PROJECT_DESCRIPTION}} slot in CLAUDE.md
#   (default: a placeholder that the user is reminded to edit).
# --mainline overrides auto-detected default branch (`main` or `master`).
#
# What it does (idempotent — safe to re-run):
#   1. Copies pack/{skills,agents,commands,hooks}/* into TARGET_DIR/.claude/
#   2. Sets executable bit on the doc-drift-detector hook.
#   3. Merges pack/hooks/settings.json.fragment into .claude/settings.json
#      (preserves any existing keys; appends our hook entry if missing).
#   4. Copies pack/state.md.template to .claude/state.md (only if missing).
#   5. Copies pack/CLAUDE.md.template to CLAUDE.md at TARGET_DIR root with
#      slot-fills applied (only if CLAUDE.md does not yet exist; warns otherwise).
#   6. Ensures TARGET_DIR/.gitignore contains `__pycache__/` and `*.pyc`.
#
# What it doesn't do:
#   - Does not git-init, branch, or commit anything in the target.
#   - Does not overwrite an existing CLAUDE.md, settings.json, or state.md.
#   - Does not install Claude Code itself or any other tooling.

set -euo pipefail

# --- Locate the pack relative to this script -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$SCRIPT_DIR/pack"

if [[ ! -d "$PACK_DIR" ]]; then
  echo "error: cannot find pack/ next to install.sh (looked in $PACK_DIR)" >&2
  exit 1
fi

# --- Parse args ----------------------------------------------------------------
TARGET=""
PROJECT_NAME=""
DESCRIPTION=""
MAINLINE=""

DESCRIPTION_PLACEHOLDER="(Add a one-line project description here.)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      PROJECT_NAME="$2"; shift 2 ;;
    --description)
      DESCRIPTION="$2"; shift 2 ;;
    --mainline)
      MAINLINE="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,30p' "$0"; exit 0 ;;
    -*)
      echo "error: unknown flag $1" >&2; exit 2 ;;
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"; else
        echo "error: extra positional arg $1" >&2; exit 2
      fi
      shift ;;
  esac
done

TARGET="${TARGET:-.}"
TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -d "$TARGET" ]]; then
  echo "error: target dir does not exist: $TARGET" >&2
  exit 1
fi

PROJECT_NAME="${PROJECT_NAME:-$(basename "$TARGET")}"
DESCRIPTION_FILLED=1
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="$DESCRIPTION_PLACEHOLDER"
  DESCRIPTION_FILLED=0
fi

# --- Auto-detect mainline branch -----------------------------------------------
if [[ -z "$MAINLINE" ]]; then
  if [[ -d "$TARGET/.git" ]]; then
    MAINLINE="$(git -C "$TARGET" symbolic-ref --short HEAD 2>/dev/null || true)"
    if [[ -z "$MAINLINE" || "$MAINLINE" == "HEAD" ]]; then
      # Look for main first, then master, then fall back to "main"
      if git -C "$TARGET" show-ref --verify --quiet refs/heads/main; then
        MAINLINE="main"
      elif git -C "$TARGET" show-ref --verify --quiet refs/heads/master; then
        MAINLINE="master"
      else
        MAINLINE="main"
      fi
    fi
  else
    MAINLINE="main"
  fi
fi

echo "==> Installing devkit pack into: $TARGET"
echo "    project name : $PROJECT_NAME"
echo "    mainline     : $MAINLINE"

# --- 1. Copy pack/{skills,agents,commands,hooks}/* into .claude/ ---------------
CLAUDE_DIR="$TARGET/.claude"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks"

copy_tree() {
  local src="$1" dst="$2"
  # Copy contents (not the dir itself) preserving structure.
  # rsync isn't always available; use cp -R with trailing /.
  cp -R "$src"/. "$dst"/
}

echo "==> Copying skills/ agents/ commands/ hooks/"
copy_tree "$PACK_DIR/skills"   "$CLAUDE_DIR/skills"
copy_tree "$PACK_DIR/agents"   "$CLAUDE_DIR/agents"
copy_tree "$PACK_DIR/commands" "$CLAUDE_DIR/commands"
copy_tree "$PACK_DIR/hooks"    "$CLAUDE_DIR/hooks"

# Don't ship the JSON fragment in the installed tree; it's an install-time artifact.
rm -f "$CLAUDE_DIR/hooks/settings.json.fragment"

# --- 2. Set hook executable bit ------------------------------------------------
HOOK="$CLAUDE_DIR/hooks/doc-drift-detector.py"
if [[ -f "$HOOK" ]]; then
  chmod +x "$HOOK"
  echo "==> Marked hook executable: $HOOK"
else
  echo "warn: hook not found at $HOOK (skipping chmod)" >&2
fi

# --- 3. Merge settings.json ----------------------------------------------------
SETTINGS="$CLAUDE_DIR/settings.json"
FRAGMENT="$PACK_DIR/hooks/settings.json.fragment"

if [[ ! -f "$FRAGMENT" ]]; then
  echo "error: settings fragment missing at $FRAGMENT" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS" ]]; then
  echo "==> Creating .claude/settings.json from fragment"
  cp "$FRAGMENT" "$SETTINGS"
else
  echo "==> Merging fragment into existing .claude/settings.json"
  # Use python3 for a non-destructive merge. The fragment only adds a
  # PostToolUse hook entry; if an equivalent entry already exists (same
  # command), we skip it to keep installs idempotent.
  python3 - "$SETTINGS" "$FRAGMENT" <<'PY'
import json, sys, pathlib

settings_path = pathlib.Path(sys.argv[1])
fragment_path = pathlib.Path(sys.argv[2])

settings = json.loads(settings_path.read_text())
fragment = json.loads(fragment_path.read_text())

# Walk fragment.hooks.<event>[] and add any entries not already present in
# settings.hooks.<event>[]. Identity is the (matcher, hook command) pair so
# re-runs don't duplicate.
def hook_id(matcher_entry):
    cmds = tuple(
        (h.get("type"), h.get("command"))
        for h in matcher_entry.get("hooks", [])
    )
    return (matcher_entry.get("matcher"), cmds)

settings.setdefault("hooks", {})
for event, entries in fragment.get("hooks", {}).items():
    existing = settings["hooks"].setdefault(event, [])
    existing_ids = {hook_id(e) for e in existing}
    for entry in entries:
        if hook_id(entry) not in existing_ids:
            existing.append(entry)

settings_path.write_text(json.dumps(settings, indent=2) + "\n")
PY
fi

# --- 4. Stamp state.md.template if missing -------------------------------------
STATE="$CLAUDE_DIR/state.md"
if [[ -f "$STATE" ]]; then
  echo "==> .claude/state.md already exists; leaving untouched"
else
  echo "==> Creating .claude/state.md from template"
  # Substitute the mainline branch into the template's "Active branch" line.
  sed "s|^\*\*Active branch:\*\* main$|**Active branch:** $MAINLINE|" \
      "$PACK_DIR/state.md.template" > "$STATE"
fi

# --- 5. Stamp CLAUDE.md.template if missing ------------------------------------
CLAUDE_MD="$TARGET/CLAUDE.md"
TEMPLATE="$PACK_DIR/CLAUDE.md.template"

if [[ -f "$CLAUDE_MD" ]]; then
  cat >&2 <<EOF
==> CLAUDE.md already exists at $CLAUDE_MD; leaving untouched.
    Review pack/CLAUDE.md.template and merge its 'Memory layout',
    'Workflow commands', 'Commit cadence', and 'Automated guards'
    sections into your existing CLAUDE.md by hand.
EOF
else
  echo "==> Creating CLAUDE.md from template"
  # Slot-fill {{PROJECT_NAME}} and {{ONE_LINE_PROJECT_DESCRIPTION}}; leave
  # {{LIST_PROJECT_CONVENTIONS_HERE}} as a placeholder for the user to fill in.
  # Escape `&`, `|`, and `\` in user-supplied values before passing to sed.
  esc() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }
  sed -e "s|{{PROJECT_NAME}}|$(esc "$PROJECT_NAME")|g" \
      -e "s|{{ONE_LINE_PROJECT_DESCRIPTION}}|$(esc "$DESCRIPTION")|g" \
      "$TEMPLATE" > "$CLAUDE_MD"
fi

# --- 6. Ensure .gitignore covers Python build artifacts ------------------------
GITIGNORE="$TARGET/.gitignore"
ensure_gitignore_line() {
  local line="$1"
  if [[ -f "$GITIGNORE" ]] && grep -Fxq "$line" "$GITIGNORE"; then
    return 0
  fi
  if [[ ! -f "$GITIGNORE" ]]; then
    : > "$GITIGNORE"
  fi
  # Add a separator comment the first time we touch it for the devkit pack.
  if ! grep -q '# added by devkit install.sh' "$GITIGNORE" 2>/dev/null; then
    {
      echo ""
      echo "# added by devkit install.sh"
    } >> "$GITIGNORE"
  fi
  echo "$line" >> "$GITIGNORE"
  echo "==> Added '$line' to .gitignore"
}

ensure_gitignore_line "__pycache__/"
ensure_gitignore_line "*.pyc"

# --- Done ----------------------------------------------------------------------
echo ""
echo "==> Install complete."
echo ""
echo "Next steps:"
step=1
if [[ -f "$CLAUDE_MD" ]]; then
  # Only emit the slot-fill reminders if we either created the CLAUDE.md just
  # now OR the slots still appear in the file (defensive check for re-runs).
  if grep -q '{{LIST_PROJECT_CONVENTIONS_HERE}}' "$CLAUDE_MD" 2>/dev/null; then
    echo "  $step. Open CLAUDE.md and fill the {{LIST_PROJECT_CONVENTIONS_HERE}} slot with"
    echo "     your project's load-bearing conventions (language, test runner, framework,"
    echo "     style rules)."
    step=$((step + 1))
  fi
  if [[ "$DESCRIPTION_FILLED" -eq 0 ]] && grep -Fq "$DESCRIPTION_PLACEHOLDER" "$CLAUDE_MD" 2>/dev/null; then
    echo "  $step. Replace the placeholder description on line 3 of CLAUDE.md with a"
    echo "     real one-line description (or re-run install with --description \"...\")."
    step=$((step + 1))
  fi
fi
echo "  $step. Restart Claude Code so it picks up the new .claude/ contents."
step=$((step + 1))
echo "  $step. Run /feature-start \"<short description>\" to begin your first feature."
echo ""
echo "See README.md for the full workflow and docs/design/ for the rationale."
