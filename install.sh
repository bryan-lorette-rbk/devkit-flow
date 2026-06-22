#!/usr/bin/env bash
# install.sh — install or update the devkit Claude Code skill-pack in a target project.
#
# Usage:
#   ./install.sh [TARGET_DIR] [flags]
#
# TARGET_DIR defaults to the current directory.
#
# Flags:
#   --project-name NAME     fill {{PROJECT_NAME}} in CLAUDE.md (default: basename TARGET_DIR)
#   --description TEXT      fill {{ONE_LINE_PROJECT_DESCRIPTION}} (default: a placeholder)
#   --mainline BRANCH       override auto-detected default branch (main / master)
#   --force                 in update mode, overwrite locally-modified files (otherwise skipped)
#   --dry-run               show the plan and exit without writing anything
#   --claude-md-only        skip pack file install; only run the CLAUDE.md handling step
#                           (re-prompt to add the orientation reference, with diff preview).
#                           Use after declining the prompt at install or after a pack update
#                           changed the template. For richer reconciliation, use the
#                           /claude-md-merge slash command from a Claude Code session.
#   --help / -h             show this help
#
# Modes:
#   - Fresh install: target has no .claude/.devkit-manifest.json.
#       Copies pack files, stamps templates, sets up settings.json + .gitignore.
#   - Update:       target has a manifest from a prior install.
#       Computes per-file plan (UPDATE / SKIP / NEW / UNCHANGED), shows it,
#       asks confirmation, applies. Locally-modified files are SKIPped unless
#       --force is passed. CLAUDE.md and state.md are never auto-overwritten;
#       template changes are surfaced as advisory diffs.
#
# After either path, writes:
#   <target>/.claude/.devkit-manifest.json    (version + file hashes for future updates)
#   <target>/.claude/.devkit-version          (version string, convenience)
#
# Idempotent. Safe to re-run.

set -euo pipefail

# --- Sanity: must run under bash ----------------------------------------------
# The shebang invokes bash when this file is executed directly, but it can be
# bypassed by `zsh install.sh`, `sh install.sh`, or sourcing from a non-bash
# shell. Fail fast and clearly if that happened — several constructs below
# (parameter-prompt `read -p`, `local`, set -u semantics) differ between bash
# and other shells, and a partial run would leave the target in a confusing
# state.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "error: install.sh must be run under bash." >&2
  echo "       Detected non-bash shell (perhaps zsh, sh, or sourced from one)." >&2
  echo "       Run as:  bash install.sh [TARGET_DIR] [flags]" >&2
  echo "                ./install.sh [TARGET_DIR] [flags]   (uses the shebang)" >&2
  echo "       Do NOT use: source ./install.sh, . install.sh, zsh install.sh" >&2
  exit 1
fi

# --- Locate the pack relative to this script -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$SCRIPT_DIR/pack"
LIB="$SCRIPT_DIR/install_lib.py"
VERSION_FILE="$SCRIPT_DIR/VERSION"

if [[ ! -d "$PACK_DIR" ]]; then
  echo "error: cannot find pack/ next to install.sh (looked in $PACK_DIR)" >&2
  exit 1
fi
if [[ ! -f "$LIB" ]]; then
  echo "error: cannot find install_lib.py next to install.sh (looked in $LIB)" >&2
  exit 1
fi
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: cannot find VERSION next to install.sh (looked in $VERSION_FILE)" >&2
  exit 1
fi

PACK_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# --- Parse args ----------------------------------------------------------------
TARGET=""
PROJECT_NAME=""
DESCRIPTION=""
MAINLINE=""
FORCE=0
DRY_RUN=0
CLAUDE_MD_ONLY=0

DESCRIPTION_PLACEHOLDER="(Add a one-line project description here.)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      PROJECT_NAME="$2"; shift 2 ;;
    --description)
      DESCRIPTION="$2"; shift 2 ;;
    --mainline)
      MAINLINE="$2"; shift 2 ;;
    --force)
      FORCE=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --claude-md-only)
      CLAUDE_MD_ONLY=1; shift ;;
    --help|-h)
      sed -n '2,35p' "$0"; exit 0 ;;
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
      if   git -C "$TARGET" show-ref --verify --quiet refs/heads/main;   then MAINLINE="main"
      elif git -C "$TARGET" show-ref --verify --quiet refs/heads/master; then MAINLINE="master"
      else MAINLINE="main"
      fi
    fi
  else
    MAINLINE="main"
  fi
fi

CLAUDE_DIR="$TARGET/.claude"
MANIFEST="$CLAUDE_DIR/.devkit-manifest.json"
VERSION_STAMP="$CLAUDE_DIR/.devkit-version"

# --- Detect mode ---------------------------------------------------------------
INSTALLED_VERSION="$(python3 "$LIB" manifest-read "$MANIFEST" 2>/dev/null || true)"
if [[ -n "$INSTALLED_VERSION" ]]; then
  MODE="update"
else
  MODE="fresh"
fi

echo "==> Target            : $TARGET"
echo "==> Pack version      : $PACK_VERSION"
if [[ "$MODE" == "update" ]]; then
  echo "==> Installed version : $INSTALLED_VERSION (update mode)"
else
  echo "==> Installed version : (none) — fresh install mode"
fi
echo "==> Project name      : $PROJECT_NAME"
echo "==> Mainline          : $MAINLINE"
[[ "$DRY_RUN" -eq 1 ]] && echo "==> DRY RUN — no files will be written"
echo ""

# --- Helpers -------------------------------------------------------------------
copy_file() {  # copy_file SRC DST   — creates parent dirs as needed
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

ensure_gitignore_line() {
  local line="$1"
  local gi="$TARGET/.gitignore"
  if [[ -f "$gi" ]] && grep -Fxq "$line" "$gi"; then return 0; fi
  if [[ ! -f "$gi" ]]; then : > "$gi"; fi
  if ! grep -q '# added by devkit install.sh' "$gi" 2>/dev/null; then
    { echo ""; echo "# added by devkit install.sh"; } >> "$gi"
  fi
  echo "$line" >> "$gi"
  echo "    + .gitignore: $line"
}

# Merge settings.json fragment into existing settings, or create from fragment.
install_or_merge_settings() {
  local settings="$CLAUDE_DIR/settings.json"
  local fragment="$PACK_DIR/hooks/settings.json.fragment"
  if [[ ! -f "$settings" ]]; then
    copy_file "$fragment" "$settings"
    echo "    + .claude/settings.json (created from fragment)"
    return 0
  fi
  python3 - "$settings" "$fragment" <<'PY'
import json, sys, pathlib
settings_path = pathlib.Path(sys.argv[1])
fragment_path = pathlib.Path(sys.argv[2])
settings = json.loads(settings_path.read_text())
fragment = json.loads(fragment_path.read_text())
def hook_id(entry):
    cmds = tuple((h.get("type"), h.get("command")) for h in entry.get("hooks", []))
    return (entry.get("matcher"), cmds)
changed = False
settings.setdefault("hooks", {})
for event, entries in fragment.get("hooks", {}).items():
    existing = settings["hooks"].setdefault(event, [])
    existing_ids = {hook_id(e) for e in existing}
    for entry in entries:
        if hook_id(entry) not in existing_ids:
            existing.append(entry); changed = True
if changed:
    settings_path.write_text(json.dumps(settings, indent=2) + "\n")
PY
  echo "    ~ .claude/settings.json (hook entries merged if missing)"
}

# Stamp CLAUDE.md.template into target/CLAUDE.md with slot-fills.
stamp_claude_md() {
  local template="$PACK_DIR/CLAUDE.md.template"
  local out="$TARGET/CLAUDE.md"
  local esc_name esc_desc
  esc_name="$(printf '%s' "$PROJECT_NAME" | sed -e 's/[&|\\]/\\&/g')"
  esc_desc="$(printf '%s' "$DESCRIPTION"  | sed -e 's/[&|\\]/\\&/g')"
  sed -e "s|{{PROJECT_NAME}}|$esc_name|g" \
      -e "s|{{ONE_LINE_PROJECT_DESCRIPTION}}|$esc_desc|g" \
      "$template" > "$out"
}

# Stamp state.md.template into target/.claude/state.md with mainline slot.
stamp_state_md() {
  local template="$PACK_DIR/state.md.template"
  local out="$CLAUDE_DIR/state.md"
  sed "s|^\*\*Active branch:\*\* main$|**Active branch:** $MAINLINE|" "$template" > "$out"
}

# Set hook executable bit.
mark_hook_exec() {
  local hook="$CLAUDE_DIR/hooks/doc-drift-detector.py"
  [[ -f "$hook" ]] && chmod +x "$hook"
}

# --- CLAUDE.md handling -------------------------------------------------------
# The pack's bulky orientation content lives in .claude/devkit-orientation.md
# (pack-owned, auto-updated). CLAUDE.md only needs a one-line reference to that
# file so Claude Code reads it when loading project memory. Cases:
#   (a) no CLAUDE.md       → stamp the slim template.
#   (b) CLAUDE.md exists,
#       reference present  → nothing to do.
#   (c) CLAUDE.md exists,
#       reference missing  → show diff preview, propose appending, ask.
# Case (c) only fires on fresh install OR when --claude-md-only is set. On a
# normal update with an existing CLAUDE.md, the TEMPLATE-CHANGED advisory in
# the plan-summary block handles pack-template churn instead.
ORIENTATION_REF_LINE='> **devkit pack:** see `.claude/devkit-orientation.md` for the pack'\''s workflow commands, memory layout, commit cadence, and automated guards.'

CLAUDE_MD_CREATED=0
CLAUDE_MD_NEEDS_REFERENCE=0

handle_claude_md_step() {
  if [[ ! -f "$TARGET/CLAUDE.md" ]]; then
    stamp_claude_md
    CLAUDE_MD_CREATED=1
    echo "    + CLAUDE.md (stamped from template)"
    return 0
  fi

  if [[ "$MODE" != "fresh" && "$CLAUDE_MD_ONLY" -eq 0 ]]; then
    # Existing CLAUDE.md + normal update mode: don't re-nag every update.
    # TEMPLATE-CHANGED advisory handles pack-template churn separately.
    return 0
  fi

  if grep -Fq ".claude/devkit-orientation.md" "$TARGET/CLAUDE.md"; then
    echo "    = CLAUDE.md already references .claude/devkit-orientation.md; leaving untouched."
    return 0
  fi

  cat <<EOF

  ! CLAUDE.md exists at $TARGET/CLAUDE.md and does not reference the orientation file.
    The devkit pack needs this one line somewhere in CLAUDE.md so the
    orientation file is read when Claude Code loads project memory:

      $ORIENTATION_REF_LINE

EOF

  local preview_before preview_after
  preview_before="$(mktemp)"
  preview_after="$(mktemp)"
  tail -3 "$TARGET/CLAUDE.md" > "$preview_before"
  { tail -3 "$TARGET/CLAUDE.md"; echo ""; echo "$ORIENTATION_REF_LINE"; } > "$preview_after"
  echo "  Proposed change (last 3 lines of CLAUDE.md, current vs after append):"
  echo ""
  # `diff` returns 1 when files differ — that's the expected case here; absorb it
  # so `set -euo pipefail` doesn't kill the script on a successful preview.
  { diff -u --label "CLAUDE.md (current)" --label "CLAUDE.md (after append)" \
    "$preview_before" "$preview_after" 2>/dev/null || true; } | sed 's/^/    /'
  echo ""
  rm -f "$preview_before" "$preview_after"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  (--dry-run: would prompt to append; not asking)"
    return 0
  fi

  printf '  Append the reference to the end of CLAUDE.md now? [Y/n]\n'
  printf '  (Decline and run /claude-md-merge in a Claude Code session for a\n'
  printf '   structured section-by-section merge instead.) '
  read -r ans
  case "$ans" in
    n|N|no|NO)
      CLAUDE_MD_NEEDS_REFERENCE=1
      echo "  Skipped. Add the reference by hand, or run /claude-md-merge for a structured merge."
      ;;
    *)
      printf '\n%s\n' "$ORIENTATION_REF_LINE" >> "$TARGET/CLAUDE.md"
      echo "    + appended orientation reference to CLAUDE.md."
      ;;
  esac
}

# --- --claude-md-only early exit ----------------------------------------------
# When --claude-md-only is set, skip the full pack install plan and only run
# the CLAUDE.md handling step. Useful for: re-prompting after a declined append,
# re-merging after a template change, or one-off reconciliation. For richer
# section-by-section reconciliation, the user runs /claude-md-merge from a
# Claude Code session instead.
if [[ "$CLAUDE_MD_ONLY" -eq 1 ]]; then
  echo "==> --claude-md-only: skipping pack file install; running CLAUDE.md handling only."
  echo ""
  handle_claude_md_step
  echo ""
  echo "==> --claude-md-only complete."
  exit 0
fi

# --- Compute plan (both modes) -------------------------------------------------
# For fresh install the plan is mostly "NEW" entries; for update it's mixed.
PLAN="$(python3 "$LIB" plan "$PACK_DIR" "$TARGET" "$MANIFEST" "$PACK_VERSION")"

# --- Categorize plan -----------------------------------------------------------
# Pre-init as empty arrays (set -u + bash 3.2 trips on `declare -a` alone).
FILES_UPDATE=(); FILES_SKIP=(); FILES_NEW=(); FILES_UNCHANGED=()
TEMPLATES_CHANGED=(); TEMPLATES_UNCHANGED=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  verb="${line%% *}"
  payload="${line#* }"
  case "$verb" in
    UPDATE)             FILES_UPDATE+=("$payload") ;;
    SKIP)               FILES_SKIP+=("$payload") ;;
    NEW)                FILES_NEW+=("$payload") ;;
    UNCHANGED)          FILES_UNCHANGED+=("$payload") ;;
    TEMPLATE-CHANGED)   TEMPLATES_CHANGED+=("$payload") ;;
    TEMPLATE-UNCHANGED) TEMPLATES_UNCHANGED+=("$payload") ;;
  esac
done <<< "$PLAN"

print_count() {
  local label="$1" count="$2"
  printf "    %-12s %d\n" "$label" "$count"
}

echo "Plan summary:"
print_count "update"    "${#FILES_UPDATE[@]}"
print_count "new"       "${#FILES_NEW[@]}"
print_count "skip"      "${#FILES_SKIP[@]}"
print_count "unchanged" "${#FILES_UNCHANGED[@]}"
echo ""

if [[ ${#FILES_NEW[@]} -gt 0 ]]; then
  echo "  New files:"; for f in "${FILES_NEW[@]}"; do echo "    + $f"; done; echo ""
fi
if [[ ${#FILES_UPDATE[@]} -gt 0 ]]; then
  echo "  Updates:";   for f in "${FILES_UPDATE[@]}"; do echo "    ~ $f"; done; echo ""
fi
if [[ ${#FILES_SKIP[@]} -gt 0 ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    echo "  Force-overwriting locally-modified files (backed up to .devkit-bak/):"
    for f in "${FILES_SKIP[@]}"; do echo "    ! $f"; done; echo ""
  else
    echo "  Locally-modified — will be SKIPPED (pass --force to overwrite):"
    for f in "${FILES_SKIP[@]}"; do echo "    - $f"; done; echo ""
  fi
fi

# Template advisories
if [[ "$MODE" == "update" && ${#TEMPLATES_CHANGED[@]} -gt 0 ]]; then
  for t in "${TEMPLATES_CHANGED[@]}"; do
    case "$t" in
      CLAUDE.md.template)
        cat <<EOF
  ! CLAUDE.md.template changed between installed and current pack version.
    Your CLAUDE.md is not auto-modified. Two paths to reconcile:
      (a) Run \`/claude-md-merge\` in a Claude Code session for a structured
          section-by-section walk-through (handles renames, equivalence, partial
          overlap — anything more than a one-line append).
      (b) Manually diff and merge:
            diff $TARGET/CLAUDE.md $PACK_DIR/CLAUDE.md.template

EOF
        ;;
      state.md.template)
        cat <<EOF
  ! state.md.template changed; your .claude/state.md is not auto-modified
    (it's your active working pointer). Compare manually if curious:
      diff $CLAUDE_DIR/state.md $PACK_DIR/state.md.template

EOF
        ;;
    esac
  done
fi

# --- Bail out on dry run -------------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> Dry run complete; no files written."
  exit 0
fi

# --- Update-mode confirmation --------------------------------------------------
# Skip the prompt if nothing meaningful would change (only unchanged + templates).
need_confirm=0
[[ ${#FILES_UPDATE[@]} -gt 0 ]] && need_confirm=1
[[ ${#FILES_NEW[@]}    -gt 0 ]] && need_confirm=1
[[ "$FORCE" -eq 1 && ${#FILES_SKIP[@]} -gt 0 ]] && need_confirm=1

if [[ "$MODE" == "update" && "$need_confirm" -eq 1 ]]; then
  # Portable prompt: `read -p` is bash-only; printing the prompt explicitly
  # works under any POSIX-ish shell that happens to invoke this script.
  printf 'Proceed with update? [y/N] '
  read -r ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "==> Aborted by user."; exit 0 ;;
  esac
fi

# --- Apply ---------------------------------------------------------------------
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/references"

# Helper: pack-relative path for a given .claude-relative target path.
# (Both share the same suffix after the .claude/ prefix, e.g.
#  .claude/skills/engineer/SKILL.md -> skills/engineer/SKILL.md in pack/)
pack_path_for() { echo "${1#.claude/}"; }

BAK_DIR="$CLAUDE_DIR/.devkit-bak"

write_one() {  # write_one TARGET_REL_PATH [backup-original?]
  local rel="$1" backup="${2:-0}"
  local pack_rel; pack_rel="$(pack_path_for "$rel")"
  local src="$PACK_DIR/$pack_rel"
  local dst="$TARGET/$rel"
  if [[ "$backup" -eq 1 && -f "$dst" ]]; then
    local bak="$BAK_DIR/$rel.$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$(dirname "$bak")"
    cp "$dst" "$bak"
    echo "    ! backed up to ${bak#$TARGET/}"
  fi
  copy_file "$src" "$dst"
}

if [[ ${#FILES_NEW[@]}    -gt 0 ]]; then for rel in "${FILES_NEW[@]}";    do write_one "$rel" 0; done; fi
if [[ ${#FILES_UPDATE[@]} -gt 0 ]]; then for rel in "${FILES_UPDATE[@]}"; do write_one "$rel" 0; done; fi
if [[ "$FORCE" -eq 1 && ${#FILES_SKIP[@]} -gt 0 ]]; then
  for rel in "${FILES_SKIP[@]}"; do write_one "$rel" 1; done
fi

# These steps run on both modes; they're individually idempotent.
mark_hook_exec
install_or_merge_settings

# state.md: only stamp on fresh install (never clobber an active working pointer).
if [[ ! -f "$CLAUDE_DIR/state.md" ]]; then
  stamp_state_md
  echo "    + .claude/state.md (stamped from template)"
fi

# CLAUDE.md handling (see the function definition near the top of this script
# for the case logic, the diff preview, and the --claude-md-only flag).
handle_claude_md_step

# .gitignore
ensure_gitignore_line "__pycache__/"
ensure_gitignore_line "*.pyc"

# --- Write manifest + version stamp --------------------------------------------
python3 "$LIB" manifest-write "$PACK_DIR" "$TARGET" "$MANIFEST" "$PACK_VERSION"
printf '%s\n' "$PACK_VERSION" > "$VERSION_STAMP"

# --- Done ----------------------------------------------------------------------
echo ""
if [[ "$MODE" == "update" ]]; then
  echo "==> Update complete. Now at devkit $PACK_VERSION."
else
  echo "==> Install complete. devkit $PACK_VERSION."
fi

echo ""
echo "Next steps:"
step=1
if [[ "$CLAUDE_MD_CREATED" -eq 1 ]]; then
  if grep -q '{{LIST_PROJECT_CONVENTIONS_HERE}}' "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "  $step. Open CLAUDE.md and fill the {{LIST_PROJECT_CONVENTIONS_HERE}} slot with"
    echo "     your project's load-bearing conventions (language, test runner, framework,"
    echo "     style rules)."
    step=$((step + 1))
  fi
  if [[ "$DESCRIPTION_FILLED" -eq 0 ]] && grep -Fq "$DESCRIPTION_PLACEHOLDER" "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "  $step. Replace the placeholder description on line 3 of CLAUDE.md with a"
    echo "     real one-line description (or re-run install with --description \"...\")."
    step=$((step + 1))
  fi
fi
if [[ "$MODE" == "update" && ${#TEMPLATES_CHANGED[@]} -gt 0 ]]; then
  echo "  $step. Review the template diff(s) flagged above and merge into your"
  echo "     CLAUDE.md by hand."
  step=$((step + 1))
fi
if [[ "$CLAUDE_MD_NEEDS_REFERENCE" -eq 1 ]]; then
  echo "  $step. Add the devkit-orientation reference line to CLAUDE.md (you"
  echo "     declined the auto-append). The line is shown above; place it"
  echo "     anywhere in CLAUDE.md."
  step=$((step + 1))
fi
echo "  $step. Restart Claude Code so it picks up the new .claude/ contents."
step=$((step + 1))
if [[ "$MODE" == "fresh" ]]; then
  echo "  $step. Existing codebase? Run /adopt first to build the baseline domain"
  echo "     docs + CLAUDE.md conventions, then /feature-start \"<short description>\"."
  echo "     Greenfield? Skip /adopt and go straight to /feature-start."
fi
echo ""
echo "See README.md for the full workflow and docs/design/ for the rationale."
