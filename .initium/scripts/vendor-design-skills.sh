#!/usr/bin/env bash
# vendor-design-skills.sh — Refresh the third-party design skills vendored into .claude/.
#
# Vendored verbatim (license files kept), pinned to the commits below:
#   frontend-design  anthropics/skills   Apache-2.0  -> .claude/skills/frontend-design/
#   impeccable       pbakaus/impeccable  Apache-2.0  -> .claude/skills/impeccable/ + .claude/agents/impeccable-*.md
#
# Impeccable's scripts/ folder (a launcher that downloads a platform binary on first run, plus
# a 1 MB font index) is deliberately not vendored: the skill falls back to reading PRODUCT.md /
# DESIGN.md directly. Projects that want the detector and live mode run `npx impeccable install`.
#
# Usage (Initium maintainers):
#   bash .initium/scripts/vendor-design-skills.sh                  # re-vendor the pinned commits
#   ANTHROPIC_REF=<sha> IMPECCABLE_REF=<sha> bash .initium/scripts/vendor-design-skills.sh
# Then update the pins below, THIRD_PARTY_NOTICES.md, and run node .initium/scripts/sync-skills.mjs.

set -euo pipefail

ANTHROPIC_REF="${ANTHROPIC_REF:-33375500bcea98d610eb30ce10ac4e59b89c390d}"
IMPECCABLE_REF="${IMPECCABLE_REF:-9d715cc4f5564a990ca8345abfdd5df6dc9b41c8}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {  # fetch <url> <ref> <dir>
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

fetch https://github.com/anthropics/skills.git "$ANTHROPIC_REF" "$WORK/anthropic"
fetch https://github.com/pbakaus/impeccable.git "$IMPECCABLE_REF" "$WORK/impeccable"

FRONTEND_DEST="$ROOT/.claude/skills/frontend-design"
rm -rf "$FRONTEND_DEST"
cp -R "$WORK/anthropic/skills/frontend-design" "$FRONTEND_DEST"

IMPECCABLE_SRC="$WORK/impeccable/plugin"
IMPECCABLE_DEST="$ROOT/.claude/skills/impeccable"
rm -rf "$IMPECCABLE_DEST"
mkdir -p "$IMPECCABLE_DEST"
cp "$IMPECCABLE_SRC/skills/impeccable/SKILL.md" "$IMPECCABLE_DEST/"
cp -R "$IMPECCABLE_SRC/skills/impeccable/reference" "$IMPECCABLE_DEST/"
cp "$WORK/impeccable/LICENSE" "$IMPECCABLE_DEST/LICENSE"
cp "$WORK/impeccable/NOTICE.md" "$IMPECCABLE_DEST/NOTICE.md"

mkdir -p "$ROOT/.claude/agents"
rm -f "$ROOT"/.claude/agents/impeccable-*.md
cp "$IMPECCABLE_SRC"/agents/impeccable-*.md "$ROOT/.claude/agents/"

echo "Vendored frontend-design@${ANTHROPIC_REF:0:7} and impeccable@${IMPECCABLE_REF:0:7}."
echo "Next: node .initium/scripts/sync-skills.mjs && update THIRD_PARTY_NOTICES.md if the pins changed."
