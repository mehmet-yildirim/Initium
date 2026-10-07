#!/usr/bin/env bash
# =============================================================================
# sync.sh — Apply Initium updates to your derived project
# =============================================================================
# Run this when Initium has been updated and you want to
# pull in improvements without overwriting your project-specific files.
#
# Usage:
#   bash .initium/scripts/sync.sh                  # Interactive mode
#   bash .initium/scripts/sync.sh --auto           # Non-interactive: apply skeleton_owned files, skip merges
#   bash .initium/scripts/sync.sh --dry-run        # Show what would change, apply nothing
#   bash .initium/scripts/sync.sh --check          # Report version status (exit 10 = update available)
#   bash .initium/scripts/sync.sh --check --json   # Same, as JSON on stdout
#
# Options:
#   --ref <tag|branch>    Sync to a specific Initium tag or branch
#   --channel tags|main   Default target when --ref is not given
#                         (default: agent.config.yaml → initium_sync.channel, else "tags")
#   --summary <file>      Write a Markdown summary (used as the PR body by CI)
#
# What it does:
#   1. Fetches the Initium repo (adds as 'skeleton' remote if needed)
#   2. Resolves the target: latest release tag (channel "tags") or main
#   3. skeleton_owned files  → auto-applied (safe overwrite)
#   4. Files removed from Initium → deleted locally if unmodified
#   5. merge_required files  → diff shown; you choose per file (skipped in --auto)
#   6. project_owned files   → never touched
#   7. Updates initium.json with the new version and commit
#
# Files listed under fileOwnership.project_owned in your local initium.json are never
# written, even when Initium owns them. On the first sync (commit is not yet recorded —
# e.g. adopting Initium in an existing repository) existing files that do not match any
# Initium version are kept, missing merge_required files are added, and missing
# project-owned templates (AGENTS.md, docs/context/, ...) are created.
#
# Exit codes: 0 success / up to date, 1 error, 10 update available (--check only)
# =============================================================================

# Must be bash (not dash). macOS `sh` is bash in POSIX mode — turn that off.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "sync.sh requires bash — run: bash .initium/scripts/sync.sh ..." >&2
  exit 1
fi
set +o posix 2>/dev/null || true

set -euo pipefail
# Disable history expansion so tokens like ^{commit} are never touched if bash -H is on.
set +H 2>/dev/null || true

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SKELETON_JSON=".initium/initium.json"
SKELETON_REMOTE="skeleton"
AGENT_CONFIG="agent.config.yaml"
EXIT_UPDATE_AVAILABLE=10
RELEASE_NOTES_MAX_LINES=400

# Colours (disabled when output is not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; NC=''
fi

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
heading() { echo -e "\n${BOLD}$*${NC}"; echo "$(printf '─%.0s' {1..60})"; }

# Extract all string values from a named JSON array (pure awk, no jq required).
# Usage: printf '%s\n' "$json_content" | _json_array <key>
_json_array() {
  local key="$1"
  awk -v k="$key" '
    index($0, "\"" k "\"") && /\[/ { in_arr=1; next }
    in_arr && /^[[:space:]]*\]/ { exit }
    in_arr {
      gsub(/^[[:space:]]*"/, "")
      gsub(/"[[:space:],]*$/, "")
      if (length) print
    }
  '
}

# Peel an annotated tag (or pass through a commit) without embedding ^{} in a larger word.
_peel_commit() {
  local rev="$1"
  local peeled="${rev}^{commit}"
  git rev-parse "$peeled"
}

# Read lines from a command into a named array (here-string — not a pipe, so no subshell).
_read_lines_into() {
  local __dest="$1"
  local __line
  while IFS= read -r __line || [ -n "$__line" ]; do
    [ -n "$__line" ] || continue
    eval "${__dest}+=(\"\$__line\")"
  done
}

# Read a scalar value from a top-level JSON string field in initium.json.
_json_field() {
  grep "\"$1\"" "$SKELETON_JSON" | head -1 | sed "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/"
}

# Read a flat key from a top-level YAML section: _yaml_value <section> <key>
_yaml_value() {
  [ -f "$AGENT_CONFIG" ] || return 0
  awk -v s="$1" -v k="$2" '
    $0 ~ "^" s ":" { in_s=1; next }
    in_s && /^[^[:space:]#]/ { exit }
    in_s && $1 == k ":" { sub(/#.*/, ""); print $2; exit }
  ' "$AGENT_CONFIG" | tr -d '"'"'"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
AUTO=false
DRY_RUN=false
CHECK_ONLY=false
JSON=false
REF=""
CHANNEL=""
SUMMARY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)     AUTO=true ;;
    --dry-run)  DRY_RUN=true ;;
    --check)    CHECK_ONLY=true ;;
    --json)     JSON=true ;;
    --ref)      REF="${2:?--ref needs a value}"; shift ;;
    --channel)  CHANNEL="${2:?--channel needs a value}"; shift ;;
    --summary)  SUMMARY_FILE="${2:?--summary needs a file path}"; shift ;;
    --help|-h)
      sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) warn "Unknown argument: $1" ;;
  esac
  shift
done

# With --json, human-readable output goes to stderr; only the JSON result goes to stdout.
if [ "$JSON" = true ]; then
  exec 3>&1 1>&2
fi

[ -n "$CHANNEL" ] || CHANNEL="$(_yaml_value initium_sync channel)"
[ -n "$CHANNEL" ] || CHANNEL="tags"
case "$CHANNEL" in tags|main) ;; *) error "Invalid channel '$CHANNEL' (expected: tags | main)" ;; esac

is_interactive() { [ "$AUTO" = false ] && [ -t 0 ]; }

# ask "<prompt>" <y|n default> — returns the default when not interactive
ask() {
  local answer
  if ! is_interactive; then [ "$2" = "y" ]; return; fi
  read -r -p "$1" answer
  answer="${answer:-$2}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

emit_output() {
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"
  return 0
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
heading "Pre-flight Checks"

[ -f "$SKELETON_JSON" ] || error ".initium/initium.json not found. Is this an Initium-based project?"
command -v git >/dev/null 2>&1 || error "git is required but not found"

if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  warn "Your working tree has uncommitted changes."
  if [ "$DRY_RUN" = false ] && [ "$CHECK_ONLY" = false ]; then
    is_interactive || error "Commit or stash your changes before a non-interactive sync."
    ask "Continue anyway? [y/N] " n || exit 1
  fi
fi

success "Working directory: $(pwd)"

# ---------------------------------------------------------------------------
# Read initium.json
# ---------------------------------------------------------------------------
SKELETON_REPO=$(_json_field repository)
CURRENT_COMMIT=$(_json_field commit)
CURRENT_SYNCED=$(_json_field syncedAt)
CURRENT_VERSION=$(_json_field version)

info "Initium repo    : $SKELETON_REPO"
info "Current version : $CURRENT_VERSION"
info "Last synced at  : $CURRENT_SYNCED"
info "Channel         : ${REF:-$CHANNEL}"

# ---------------------------------------------------------------------------
# Set up Initium remote and resolve the target
# ---------------------------------------------------------------------------
heading "Connecting to Initium Repository"

if ! git remote get-url "$SKELETON_REMOTE" &>/dev/null; then
  info "Adding Initium remote: $SKELETON_REPO"
  git remote add "$SKELETON_REMOTE" "$SKELETON_REPO"
else
  EXISTING_URL=$(git remote get-url "$SKELETON_REMOTE")
  if [ "$EXISTING_URL" != "$SKELETON_REPO" ]; then
    warn "Remote '$SKELETON_REMOTE' points to $EXISTING_URL (initium.json says $SKELETON_REPO)"
    if ask "Update remote URL? [y/N] " n || ! is_interactive; then
      git remote set-url "$SKELETON_REMOTE" "$SKELETON_REPO"
      info "Remote URL updated to $SKELETON_REPO"
    fi
  fi
fi

# Latest stable release tag (vMAJOR.MINOR.PATCH, no pre-releases)
latest_release_tag() {
  git ls-remote --tags --refs --sort=-v:refname "$SKELETON_REMOTE" 'v*' 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
}

# Fetched refs live under refs/initium/ so upstream tags never mix with project tags.
fetch_tag()    { git fetch --quiet --no-tags "$SKELETON_REMOTE" "+refs/tags/$1:refs/initium/$1"; }
fetch_branch() { git fetch --quiet --no-tags "$SKELETON_REMOTE" "+refs/heads/$1:refs/initium/$1"; }

TARGET_REF=""
TARGET_VERSION=""
info "Fetching Initium..."
if [ -n "$REF" ]; then
  if git ls-remote --exit-code --tags --refs "$SKELETON_REMOTE" "refs/tags/$REF" >/dev/null 2>&1; then
    fetch_tag "$REF"; TARGET_VERSION="${REF#v}"
  else
    fetch_branch "$REF" || error "Ref '$REF' not found in $SKELETON_REPO"
  fi
  TARGET_REF="$REF"
elif [ "$CHANNEL" = "tags" ]; then
  TARGET_REF=$(latest_release_tag)
  if [ -n "$TARGET_REF" ]; then
    fetch_tag "$TARGET_REF"; TARGET_VERSION="${TARGET_REF#v}"
  else
    warn "No release tags found in Initium — falling back to main"
    TARGET_REF="main"; fetch_branch main
  fi
else
  TARGET_REF="main"; fetch_branch main
fi

TARGET=$(_peel_commit "refs/initium/$TARGET_REF")
TARGET_SHORT=$(git rev-parse --short "$TARGET")
if [ -z "$TARGET_VERSION" ]; then
  TARGET_VERSION=$(git show "$TARGET:.initium/docs/UPDATES.md" 2>/dev/null \
    | grep -m1 "^## v" | sed 's/^## v//' | awk '{print $1}' || true)
  TARGET_VERSION="${TARGET_VERSION:-unknown}"
fi

success "Target: ${TARGET_REF} — ${TARGET_SHORT}, version ${TARGET_VERSION}"

UPDATE_AVAILABLE=true
[ "$CURRENT_COMMIT" = "$TARGET" ] && UPDATE_AVAILABLE=false
emit_output update_available "$UPDATE_AVAILABLE"
emit_output target_version "$TARGET_VERSION"
emit_output target_ref "$TARGET_REF"
emit_output current_version "$CURRENT_VERSION"

if [ "$CHECK_ONLY" = true ]; then
  if [ "$JSON" = true ]; then
    printf '{"current":"%s","latest":"%s","ref":"%s","commit":"%s","updateAvailable":%s}\n' \
      "$CURRENT_VERSION" "$TARGET_VERSION" "$TARGET_REF" "$TARGET" "$UPDATE_AVAILABLE" >&3
  fi
  if [ "$UPDATE_AVAILABLE" = true ]; then
    info "Update available: $CURRENT_VERSION → $TARGET_VERSION"
    echo "Run 'bash .initium/scripts/sync.sh' to apply updates."
    exit "$EXIT_UPDATE_AVAILABLE"
  fi
  success "Already up to date."
  exit 0
fi

if [ "$UPDATE_AVAILABLE" = false ]; then
  success "Already up to date — Initium $TARGET_VERSION matches your last sync."
  ask "Force re-sync anyway? [y/N] " n || { info "Nothing to do."; exit 0; }
else
  info "Update available: $CURRENT_VERSION → $TARGET_VERSION"
fi

# ---------------------------------------------------------------------------
# Show changelog between versions
# ---------------------------------------------------------------------------
heading "What Changed in Initium"

echo ""
echo "Commits since your last sync:"
git log --oneline "$CURRENT_COMMIT..$TARGET" 2>/dev/null || \
  git log --oneline "$TARGET" --max-count=20

echo ""
info "Full migration notes: $SKELETON_REPO/blob/$TARGET_REF/.initium/docs/UPDATES.md"
echo ""
ask "Continue with sync? [Y/n] " y || { info "Sync cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# Read file ownership lists — always from the target Initium version so newly
# added files are included, regardless of what the local initium.json says.
# ---------------------------------------------------------------------------
REMOTE_SKELETON_JSON=$(git show "$TARGET:.initium/initium.json")

SKELETON_OWNED=()
_read_lines_into SKELETON_OWNED <<< "$(printf '%s\n' "$REMOTE_SKELETON_JSON" | _json_array "skeleton_owned")"
PROJECT_OWNED=()
_read_lines_into PROJECT_OWNED <<< "$(printf '%s\n' "$REMOTE_SKELETON_JSON" | _json_array "project_owned")"
MERGE_REQUIRED=()
_read_lines_into MERGE_REQUIRED <<< "$(printf '%s\n' "$REMOTE_SKELETON_JSON" | _json_array "merge_required")"

# ---------------------------------------------------------------------------
# Get list of changed files in Initium since last sync
# ---------------------------------------------------------------------------
FIRST_SYNC=false
if [ -n "$CURRENT_COMMIT" ] && _peel_commit "$CURRENT_COMMIT" >/dev/null 2>&1; then
  CHANGED_FILES=$(git diff --name-only "$CURRENT_COMMIT" "$TARGET")
else
  # First sync — list every file tracked in the Initium tree
  FIRST_SYNC=true
  CHANGED_FILES=$(git ls-tree -r --name-only "$TARGET")
fi

APPLIED=0
SKIPPED=0
UPDATED_FILES=()
ADDED_FILES=()
REMOVED_FILES=()
KEPT_MODIFIED=()
NEEDS_MERGE=()
PROTECTED=()
EXISTING_KEPT=()

LOCAL_PROJECT_OWNED=()
_read_lines_into LOCAL_PROJECT_OWNED <<< "$(_json_array "project_owned" < "$SKELETON_JSON")"

matches_entry() {  # matches_entry <file> <entry> — exact or directory-prefix match
  case "$2" in
    */) [[ "$1" == "$2" || "$1" == "$2"* ]] ;;
    *)  [[ "$1" == "$2" ]] ;;
  esac
}

is_locally_owned() {
  local entry
  for entry in ${LOCAL_PROJECT_OWNED[@]+"${LOCAL_PROJECT_OWNED[@]}"}; do
    matches_entry "$1" "$entry" && return 0
  done
  return 1
}

# True when the local file is byte-identical to some version Initium shipped at this path.
is_initium_version() {
  local blob
  blob=$(git hash-object -- "$1")
  git log --format= --raw --no-abbrev "$TARGET" -- "$1" | awk '{print $4}' | grep -qx "$blob"
}

write_from_target() {
  mkdir -p "$(dirname "$1")"
  git show "$TARGET:$1" > "$1"
}

# ---------------------------------------------------------------------------
# Apply skeleton_owned files
# ---------------------------------------------------------------------------
heading "Applying Initium-Owned Files (safe overwrite)"

for file in $CHANGED_FILES; do
  is_skeleton_owned=false
  for owned in "${SKELETON_OWNED[@]}"; do
    if matches_entry "$file" "$owned"; then is_skeleton_owned=true; break; fi
  done
  [ "$is_skeleton_owned" = true ] || continue
  git cat-file -e "$TARGET:$file" 2>/dev/null || continue
  if is_locally_owned "$file"; then PROTECTED+=("$file"); continue; fi
  if [ "$FIRST_SYNC" = true ] && [ -f "$file" ] && ! is_initium_version "$file"; then
    warn "  Existing project file kept: $file"
    EXISTING_KEPT+=("$file")
    continue
  fi

  action="Updated"
  [ -f "$file" ] || action="Added"
  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${GREEN}[DRY-RUN WOULD $(echo "$action" | tr '[:lower:]' '[:upper:]')]${NC} $file"
  else
    write_from_target "$file"
    success "  $action: $file"
  fi
  if [ "$action" = "Added" ]; then ADDED_FILES+=("$file"); else UPDATED_FILES+=("$file"); fi
  APPLIED=$((APPLIED + 1))
done

# ---------------------------------------------------------------------------
# Add skeleton_owned files that are missing locally
# (new files added to Initium that don't appear in a normal diff
#  because the derived project never had them, or were accidentally deleted)
# ---------------------------------------------------------------------------
heading "Adding Missing Initium-Owned Files"

for file in "${SKELETON_OWNED[@]}"; do
  [[ "${file: -1}" == "/" ]] && continue
  [ -f "$file" ] && continue
  git cat-file -e "$TARGET:$file" 2>/dev/null || continue
  is_locally_owned "$file" && continue

  if [ "$DRY_RUN" = true ]; then
    echo -e "  ${GREEN}[DRY-RUN WOULD ADD]${NC} $file"
  else
    write_from_target "$file"
    success "  Added (new): $file"
  fi
  ADDED_FILES+=("$file")
  APPLIED=$((APPLIED + 1))
done

[ ${#ADDED_FILES[@]} -eq 0 ] && info "No missing Initium-owned files."

# ---------------------------------------------------------------------------
# Remove files that Initium deleted
# Candidates: the target's "removed" list plus every skeleton_owned entry in
# the local initium.json (the ownership list of the version you synced last).
# A file is deleted only if it is byte-identical to Initium's last version of
# it; locally modified copies are kept and reported.
# ---------------------------------------------------------------------------
heading "Removing Files Deleted from Initium"

REMOVAL_CANDIDATES=$(
  { printf '%s\n' "$REMOTE_SKELETON_JSON" | _json_array "removed"
    _json_array "skeleton_owned" < "$SKELETON_JSON"; } | sort -u
)

for file in $REMOVAL_CANDIDATES; do
  [[ "${file: -1}" == "/" ]] && continue
  [ -f "$file" ] || continue
  git cat-file -e "$TARGET:$file" 2>/dev/null && continue

  deleting_commit=$(git log -1 --format=%H "$TARGET" -- "$file" 2>/dev/null || true)
  if [ -z "$deleting_commit" ] || ! git cat-file -e "$deleting_commit^:$file" 2>/dev/null; then
    continue
  fi

  if git show "$deleting_commit^:$file" | cmp -s - "$file"; then
    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${GREEN}[DRY-RUN WOULD REMOVE]${NC} $file"
    else
      if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then git rm -q "$file"; else rm -f "$file"; fi
      success "  Removed: $file"
    fi
    REMOVED_FILES+=("$file")
    APPLIED=$((APPLIED + 1))
  else
    warn "  Removed in Initium but modified locally — kept: $file"
    KEPT_MODIFIED+=("$file")
  fi
done

[ ${#REMOVED_FILES[@]} -eq 0 ] && [ ${#KEPT_MODIFIED[@]} -eq 0 ] && info "No removed files to clean up."

# ---------------------------------------------------------------------------
# Identify merge_required files that changed
# ---------------------------------------------------------------------------
heading "Merge-Required Files (manual review needed)"

for file in $CHANGED_FILES; do
  is_merge=false
  for merge in "${MERGE_REQUIRED[@]}"; do
    if matches_entry "$file" "$merge"; then is_merge=true; break; fi
  done
  [ "$is_merge" = true ] || continue
  git cat-file -e "$TARGET:$file" 2>/dev/null || continue
  if is_locally_owned "$file"; then PROTECTED+=("$file"); continue; fi
  if [ "$FIRST_SYNC" = true ] && [ ! -f "$file" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${GREEN}[DRY-RUN WOULD ADD]${NC} $file"
    else
      write_from_target "$file"
      success "  Added (no local version): $file"
    fi
    ADDED_FILES+=("$file")
    APPLIED=$((APPLIED + 1))
    continue
  fi
  NEEDS_MERGE+=("$file")
done

if [ ${#NEEDS_MERGE[@]} -eq 0 ]; then
  info "No merge-required files changed in this Initium update."
else
  echo ""
  warn "These files changed in Initium but require manual merge"
  warn "because your project has likely customised them:"
  echo ""
  for file in "${NEEDS_MERGE[@]}"; do
    echo -e "  ${YELLOW}→ $file${NC}"
  done
  echo ""
  echo "For each file above:"
  echo "  1. View Initium version: git show refs/initium/$TARGET_REF:<file>"
  echo "  2. View your version: cat <file>"
  echo "  3. Apply only the relevant new sections from Initium"
  echo ""

  if [ "$DRY_RUN" = false ]; then
    for file in "${NEEDS_MERGE[@]}"; do
      if ! is_interactive; then
        warn "  Skipped (non-interactive): $file — merge manually"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo " MERGE: $file"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Diff (Initium vs your version):"
      git diff "$TARGET:$file" "$file" 2>/dev/null || \
        echo "  [file is new in Initium — no local version to diff]"
      echo ""
      echo "Options:"
      echo "  a) Overwrite with Initium version (discards your changes)"
      echo "  s) Skip this file (merge manually later)"
      echo "  o) Open both in diff tool (${VISUAL:-vimdiff})"
      read -r -p "Choice [a/S/o]: " choice
      case "$choice" in
        a|A)
          write_from_target "$file"
          success "  Overwritten: $file"
          APPLIED=$((APPLIED + 1))
          ;;
        o|O)
          SKELETON_TMP=$(mktemp /tmp/skeleton-XXXXXX)
          git show "$TARGET:$file" > "$SKELETON_TMP"
          ${VISUAL:-vimdiff} "$SKELETON_TMP" "$file" || true
          rm -f "$SKELETON_TMP"
          warn "  Review complete — your changes kept. Stage manually if you edited."
          SKIPPED=$((SKIPPED + 1))
          ;;
        *)
          warn "  Skipped: $file — merge manually"
          SKIPPED=$((SKIPPED + 1))
          ;;
      esac
    done
  fi
fi

# ---------------------------------------------------------------------------
# First sync: create project-owned templates the repository does not have yet.
# Existing files are never touched; project identity files are never copied.
# ---------------------------------------------------------------------------
ADOPT_SKIP=" README.md README.tr.md LICENSE CODE_OF_CONDUCT.md CHANGELOG.md .env .initium/initium.json "
if [ "$FIRST_SYNC" = true ]; then
  heading "Adding Missing Project Templates (first sync)"
  TEMPLATES_ADDED=0
  for entry in "${PROJECT_OWNED[@]}"; do
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      [[ "$ADOPT_SKIP" == *" $file "* ]] && continue
      [ -e "$file" ] && continue
      if [ "$DRY_RUN" = true ]; then
        echo -e "  ${GREEN}[DRY-RUN WOULD ADD]${NC} $file"
      else
        write_from_target "$file"
        success "  Added template: $file"
      fi
      ADDED_FILES+=("$file")
      APPLIED=$((APPLIED + 1))
      TEMPLATES_ADDED=$((TEMPLATES_ADDED + 1))
    done <<< "$(git ls-tree -r --name-only "$TARGET" -- "$entry")"
  done
  [ "$TEMPLATES_ADDED" -eq 0 ] && info "All project templates already exist."
fi

# ---------------------------------------------------------------------------
# Report project_owned files that were changed in Initium (informational)
# ---------------------------------------------------------------------------
PROJECT_TEMPLATE_CHANGES=()
if [ "$FIRST_SYNC" = false ]; then
  for file in $CHANGED_FILES; do
    for owned in "${PROJECT_OWNED[@]}"; do
      if matches_entry "$file" "$owned"; then PROJECT_TEMPLATE_CHANGES+=("$file"); break; fi
    done
  done
fi

if [ ${#PROJECT_TEMPLATE_CHANGES[@]} -gt 0 ]; then
  heading "Initium Template Files Changed (for your reference)"
  warn "These project-owned files were updated in the Initium template."
  warn "Review them to see if new guidance applies to your project:"
  echo ""
  for file in "${PROJECT_TEMPLATE_CHANGES[@]}"; do
    echo -e "  ${CYAN}ℹ  $file${NC}"
    echo "     → Review: git show refs/initium/$TARGET_REF:$file | head -40"
  done
fi

# ---------------------------------------------------------------------------
# Update initium.json
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = false ]; then
  heading "Updating initium.json"
  TODAY=$(date +%Y-%m-%d)

  # Pure sed, no jq required
  TMP=$(mktemp)
  sed "s|\"commit\": *\"[^\"]*\"|\"commit\": \"$TARGET\"|" "$SKELETON_JSON" \
    | sed "s|\"syncedAt\": *\"[^\"]*\"|\"syncedAt\": \"$TODAY\"|" \
    | sed "s|\"version\": *\"[^\"]*\"|\"version\": \"$TARGET_VERSION\"|" \
    > "$TMP"
  mv "$TMP" "$SKELETON_JSON"
  success "initium.json updated (version=$TARGET_VERSION, commit=$TARGET_SHORT)"
fi

# ---------------------------------------------------------------------------
# Run validator
# ---------------------------------------------------------------------------
VALIDATION="skipped"
if [ "$DRY_RUN" = false ] && [ "$APPLIED" -gt 0 ] && [ -f ".initium/scripts/validate.sh" ]; then
  heading "Validating Configuration"
  if bash .initium/scripts/validate.sh; then
    VALIDATION="passed"
  else
    VALIDATION="failed"
    warn "Validator found issues — review above"
  fi
fi

emit_output applied "$APPLIED"
emit_output merge_required "${#NEEDS_MERGE[@]}"
emit_output validation "$VALIDATION"

# ---------------------------------------------------------------------------
# Markdown summary (PR body for automated syncs)
# ---------------------------------------------------------------------------
list_md() {  # list_md <prefix> <items...>
  local prefix="$1"; shift
  if [ $# -eq 0 ]; then echo "_None_"; return; fi
  for item in "$@"; do echo "$prefix\`$item\`"; done
}

# Release notes: every UPDATES.md section newer than the current version
release_notes() {
  git show "$TARGET:.initium/docs/UPDATES.md" 2>/dev/null | awk -v cur="## v$CURRENT_VERSION" '
    /^## v/ { started=1; if (index($0, cur) == 1) exit }
    started { print }
  ' | head -n "$RELEASE_NOTES_MAX_LINES" || true
}

if [ -n "$SUMMARY_FILE" ]; then
  {
    echo "## Initium update: $CURRENT_VERSION → $TARGET_VERSION"
    echo ""
    echo "Automated sync to Initium \`$TARGET_REF\` (\`$TARGET_SHORT\`). Only Initium-owned files were"
    echo "changed; project-owned files were not touched. Validator: **$VALIDATION**."
    echo ""
    echo "### Merge manually before approving"
    echo "These files are customised per project, so the sync did not change them. Compare each with"
    echo "\`git show refs/initium/$TARGET_REF:<file>\` (after running the sync locally) and port what applies:"
    echo ""
    list_md "- [ ] " ${NEEDS_MERGE[@]+"${NEEDS_MERGE[@]}"}
    echo ""
    echo "### Removed in Initium but modified locally (kept)"
    list_md "- [ ] " ${KEPT_MODIFIED[@]+"${KEPT_MODIFIED[@]}"}
    echo ""
    echo "### Protected by local project_owned (not touched)"
    list_md "- " ${PROTECTED[@]+"${PROTECTED[@]}"}
    echo ""
    echo "### Existing project files kept on first sync"
    list_md "- [ ] " ${EXISTING_KEPT[@]+"${EXISTING_KEPT[@]}"}
    echo ""
    echo "### Project-owned templates changed upstream (for reference)"
    list_md "- " ${PROJECT_TEMPLATE_CHANGES[@]+"${PROJECT_TEMPLATE_CHANGES[@]}"}
    echo ""
    echo "<details><summary>Files updated (${#UPDATED_FILES[@]}), added (${#ADDED_FILES[@]}), removed (${#REMOVED_FILES[@]})</summary>"
    echo ""
    echo "**Updated**"; list_md "- " ${UPDATED_FILES[@]+"${UPDATED_FILES[@]}"}
    echo ""
    echo "**Added**"; list_md "- " ${ADDED_FILES[@]+"${ADDED_FILES[@]}"}
    echo ""
    echo "**Removed**"; list_md "- " ${REMOVED_FILES[@]+"${REMOVED_FILES[@]}"}
    echo ""
    echo "</details>"
    echo ""
    echo "### Release notes"
    echo ""
    release_notes
  } > "$SUMMARY_FILE"
  info "Summary written to $SUMMARY_FILE"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
heading "Sync Complete"
echo ""
echo -e "  ${GREEN}Applied (auto)${NC}   : $APPLIED files (${#REMOVED_FILES[@]} removed)"
echo -e "  ${YELLOW}Skipped (manual)${NC} : $SKIPPED files — merge these manually"
[ ${#KEPT_MODIFIED[@]} -gt 0 ] && \
  echo -e "  ${YELLOW}Kept (modified)${NC}  : ${#KEPT_MODIFIED[@]} files removed in Initium but changed locally"
[ ${#PROJECT_TEMPLATE_CHANGES[@]} -gt 0 ] && \
  echo -e "  ${CYAN}Template notices${NC} : ${#PROJECT_TEMPLATE_CHANGES[@]} project-owned files changed in Initium"
[ ${#PROTECTED[@]} -gt 0 ] && \
  echo -e "  ${CYAN}Protected${NC}        : ${#PROTECTED[@]} files listed in your local project_owned"
if [ ${#EXISTING_KEPT[@]} -gt 0 ]; then
  echo -e "  ${YELLOW}Existing kept${NC}    : ${#EXISTING_KEPT[@]} project files differ from Initium and were not overwritten:"
  for file in "${EXISTING_KEPT[@]}"; do echo "      $file"; done
  echo "    Compare: git diff refs/initium/$TARGET_REF:<file> <file>"
  echo "    Keep yours permanently: add the path to fileOwnership.project_owned in .initium/initium.json"
  echo "    Take Initium's: delete the file and run the sync again"
fi
echo ""
if [ "$DRY_RUN" = false ]; then
  echo "Suggested next steps:"
  echo "  1. Review changes: git diff"
  echo "  2. Stage and commit: git add -A && git commit -m 'chore: sync Initium to $TARGET_VERSION'"
  [ "$SKIPPED" -gt 0 ] && echo "  3. Merge skipped files manually, then commit"
else
  echo "  (Dry run — no files changed)"
fi
echo ""
