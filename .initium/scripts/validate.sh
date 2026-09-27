#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# AI Configuration Validator
# Checks that all AI tool config files are present and customized.
# =============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC} $*"; PASS=$((PASS + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $*"; WARN=$((WARN + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $*"; FAIL=$((FAIL + 1)); }

echo ""
echo "========================================"
echo "  AI Configuration Validator"
echo "========================================"

# ---------------------------------------------------------------------------
# File existence checks
# ---------------------------------------------------------------------------
echo ""
echo "--- File Presence ---"

check_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    pass "Found: $file"
    return 0
  else
    # Record and continue: under `set -e` a non-zero return would abort all remaining checks.
    fail "Missing: $file"
  fi
}

check_exists "AGENTS.md"
check_exists "CLAUDE.md"
if [ -f "CLAUDE.md" ] && ! grep -q "^@AGENTS.md" "CLAUDE.md"; then
  warn "CLAUDE.md does not import @AGENTS.md — Claude Code may follow different instructions"
fi
check_exists "SECURITY.md"
check_exists ".cursor/rules/00-project-overview.mdc"
check_exists ".cursor/rules/01-coding-standards.mdc"
check_exists ".cursor/rules/02-architecture.mdc"
check_exists ".cursor/rules/03-testing.mdc"
check_exists ".cursor/rules/04-git-workflow.mdc"
check_exists ".cursor/rules/05-security.mdc"
check_exists ".cursor/mcp.json"
check_exists ".continue/config.yaml"
check_exists ".continue/rules/01-coding-standards.md"
check_exists ".continue/rules/02-architecture.md"
check_exists ".continue/rules/03-testing.md"
check_exists ".continue/rules/04-security.md"
check_exists ".claude/commands/init.md"
check_exists ".claude/commands/requirements.md"
check_exists ".claude/commands/architect.md"
check_exists ".claude/commands/implement.md"
check_exists ".claude/commands/review.md"
check_exists ".claude/commands/qa.md"
check_exists ".claude/commands/test.md"
check_exists ".claude/commands/debug.md"
check_exists ".claude/commands/deploy.md"
check_exists ".claude/commands/migrate.md"
check_exists ".claude/commands/infra.md"
check_exists ".claude/commands/db.md"
check_exists ".claude/commands/sprint.md"
check_exists ".claude/commands/docs.md"
check_exists ".claude/commands/standup.md"
check_exists ".claude/commands/security-audit.md"
check_exists ".claude/commands/triage.md"
check_exists ".claude/commands/groom.md"
check_exists ".claude/commands/loop.md"
check_exists ".claude/commands/escalate.md"
check_exists ".claude/commands/goal.md"
check_exists ".claude/commands/help.md"
check_exists ".claude/commands/codegraph.md"
check_exists ".claude/commands/refactor.md"
check_exists ".claude/commands/upgrade.md"
check_exists ".claude/commands/perf.md"
check_exists ".claude/commands/a11y.md"
check_exists ".claude/commands/eval.md"
check_exists ".claude/commands/skill.md"

# --- OpenCode (mirrored slash commands) ---
check_exists "opencode.json"
check_exists ".opencode/README.md"
if [ -x ".initium/scripts/sync-opencode-commands.sh" ]; then
  if bash .initium/scripts/sync-opencode-commands.sh --check >/dev/null 2>&1; then
    pass "OpenCode commands in sync with .claude/commands/"
  else
    fail "OpenCode commands out of sync — run: bash .initium/scripts/sync-opencode-commands.sh"
  fi
else
  warn "Missing .initium/scripts/sync-opencode-commands.sh — cannot verify OpenCode sync"
fi

# --- Autonomous agent config & docs ---
check_exists "agent.config.yaml"
check_exists "docs/context/domain-boundaries.md"
check_exists ".initium/docs/agent/autonomous-workflow.md"
check_exists ".initium/docs/agent/escalation-protocol.md"
check_exists ".initium/docs/agent/decision-log-template.md"
check_exists ".initium/docs/agent/jira-server-setup.md"
check_exists ".initium/docs/agent/documentation-agent.md"
check_exists ".claude/commands/doc-api.md"
check_exists ".claude/commands/doc-site.md"
check_exists ".claude/commands/doc-changelog.md"
check_exists ".claude/commands/doc-schema.md"
check_exists ".agent-templates/webhook-receiver.mjs"
check_exists ".initium/docs/agent/schemas/task-state.json"
check_exists ".initium/docs/agent/schemas/decision.json"
check_exists ".initium/docs/agent/schemas/requirement-analysis.json"
check_exists ".initium/docs/agent/schemas/qa-report.json"
check_exists ".claude/hooks/post-write.mjs"
check_exists ".claude/hooks/audit-log.mjs"
check_exists ".claude/hooks/on-stop.mjs"

# --- Agent Skills (.claude/skills/<name>/SKILL.md — single source) ---
skill_count=$(find .claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$skill_count" -gt 0 ]; then
  pass "Found $skill_count skill(s) in .claude/skills/"
else
  fail "No skills found in .claude/skills/"
fi
if compgen -G ".cursor/rules/skills/*.mdc" >/dev/null; then
  warn "Legacy .cursor/rules/skills/ still present — skills now live in .claude/skills/ (see UPDATES.md v1.1.0)"
fi
check_exists ".initium/scripts/sync-skills.mjs"
if command -v node >/dev/null 2>&1; then
  if node .initium/scripts/sync-skills.mjs --check >/dev/null 2>&1; then
    pass "Skills valid; Continue rules in sync"
  else
    fail "Skill frontmatter invalid or Continue rules stale — run: node .initium/scripts/sync-skills.mjs"
  fi
else
  warn "node not found — cannot validate skills (requires Node.js 22+)"
fi

# --- Workflow docs ---
check_exists "docs/guides/workflows/01-requirements-analysis.md"
check_exists "docs/guides/workflows/02-feature-development.md"
check_exists "docs/guides/workflows/03-testing-strategy.md"
check_exists "docs/guides/workflows/04-deployment.md"
check_exists "docs/guides/workflows/05-security-evaluation.md"
check_exists "docs/guides/workflows/06-database-migrations.md"
check_exists "docs/guides/workflows/07-deployment-platforms.md"
check_exists "skills/README.md"
check_exists ".initium/docs/agent/security-evaluator.md"
check_exists ".initium/docs/agent/schemas/security-report.json"

check_exists "docs/context/project-brief.md"
check_exists "docs/context/tech-stack.md"
check_exists "docs/context/domain-boundaries.md"
check_exists "docs/context/domain-glossary.md"
check_exists "docs/architecture/overview.md"

# --- Initium sync ---
check_exists ".initium/initium.json"
check_exists ".initium/docs/UPDATES.md"
check_exists ".initium/scripts/sync.sh"
check_exists ".initium/scripts/sync.ps1"
check_exists ".initium/scripts/sync.cmd"
check_exists ".initium/scripts/check-update.mjs"
check_exists ".github/workflows/initium-sync.yml"
check_exists ".initium/docs/sync-guide.md"
check_exists ".claude/commands/sync-initium.md"

# --- Scripts ---
check_exists ".initium/scripts/setup.sh"
check_exists ".initium/scripts/setup.ps1"
check_exists ".initium/scripts/setup.cmd"
check_exists ".initium/scripts/init.sh"
check_exists ".initium/scripts/init.ps1"
check_exists ".initium/scripts/init.cmd"

# ---------------------------------------------------------------------------
# Customization checks (look for TODO placeholders)
# ---------------------------------------------------------------------------
echo ""
echo "--- Customization (TODO placeholders remaining) ---"

check_customized() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return
  fi
  local todo_count
  todo_count=$(grep -c "^TODO\|: TODO\|TODO:" "$file" 2>/dev/null || true)
  if [ "$todo_count" -eq 0 ]; then
    pass "Customized: $file"
  else
    warn "$file has $todo_count TODO(s) remaining"
  fi
}

check_customized "AGENTS.md"
check_customized "SECURITY.md"
check_customized ".initium/initium.json"
check_customized ".cursor/rules/00-project-overview.mdc"
check_customized "docs/context/project-brief.md"
check_customized "docs/context/tech-stack.md"
check_customized "docs/context/domain-boundaries.md"
check_customized "docs/architecture/overview.md"
check_customized "agent.config.yaml"

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
echo ""
echo "--- Environment ---"

if [ -f ".env" ]; then
  pass "Found: .env"
else
  warn "Missing .env — copy from .env.example and fill in values"
fi

if [ -f ".env.example" ]; then
  pass "Found: .env.example"
else
  warn "Missing .env.example — create one to document required variables"
fi

# ---------------------------------------------------------------------------
# Git check
# ---------------------------------------------------------------------------
echo ""
echo "--- Git ---"

if [ -d ".git" ]; then
  pass "Git repository initialized"
else
  fail "No git repository — run: git init"
fi

if git remote get-url origin &>/dev/null 2>&1; then
  REMOTE=$(git remote get-url origin)
  pass "Remote origin: $REMOTE"
else
  warn "No remote origin set — run: git remote add origin <url>"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Results"
echo "========================================"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Action required: fix FAIL items before starting development.${NC}"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}Warnings present: review WARN items and customize as needed.${NC}"
  exit 0
else
  echo -e "${GREEN}All checks passed! You're ready to code.${NC}"
  exit 0
fi
