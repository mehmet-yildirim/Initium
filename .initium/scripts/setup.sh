#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Initium — Project Setup Script
# =============================================================================
# Run this once after cloning Initium to initialize your project.
# =============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "========================================"
echo "  AI-Native Project Setup"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Initialize git repository (if not already a repo)
# ---------------------------------------------------------------------------
if [ ! -d ".git" ]; then
  info "Initializing git repository..."
  git init
  success "Git repository initialized."
else
  info "Git repository already exists, skipping init."
fi

# ---------------------------------------------------------------------------
# 2. Remove Initium remote origin (if inherited from clone)
# ---------------------------------------------------------------------------
if git remote get-url origin &>/dev/null 2>&1; then
  REMOTE=$(git remote get-url origin)
  if [[ "$REMOTE" == *"Initium"* ]]; then
    warn "Removing Initium remote origin: $REMOTE"
    git remote remove origin
    success "Removed Initium remote. Add your own with: git remote add origin <url>"
  fi
fi

# ---------------------------------------------------------------------------
# 2a. Enable the guardrail pre-commit hook (.githooks/pre-commit)
# ---------------------------------------------------------------------------
HOOKS_PATH=$(git config --get core.hooksPath || true)
if [ -z "$HOOKS_PATH" ]; then
  git config core.hooksPath .githooks
  success "Guardrail pre-commit hook enabled (core.hooksPath=.githooks)."
elif [ "$HOOKS_PATH" = ".githooks" ]; then
  info "Guardrail pre-commit hook already enabled."
else
  warn "core.hooksPath is '$HOOKS_PATH' (e.g. husky). Call 'sh .githooks/pre-commit' from your pre-commit hook to keep guardrails."
fi

# ---------------------------------------------------------------------------
# 3. Create .env from .env.example if it doesn't exist
# ---------------------------------------------------------------------------
if [ -f ".env.example" ] && [ ! -f ".env" ]; then
  info "Creating .env from .env.example..."
  cp .env.example .env
  success "Created .env — fill in your values before starting development."
elif [ ! -f ".env.example" ]; then
  warn "No .env.example found. Create one with your required environment variables."
else
  info ".env already exists, skipping."
fi

# ---------------------------------------------------------------------------
# 4. Validate required AI tool configurations
# ---------------------------------------------------------------------------
info "Checking AI tool configuration files..."

MISSING_CONFIG=false

check_file() {
  local file="$1"
  local label="$2"
  if [ -f "$file" ]; then
    success "$label: $file"
  else
    warn "$label not found: $file"
    MISSING_CONFIG=true
  fi
}

check_file "AGENTS.md"                    "Agent instructions (all tools)"
check_file "CLAUDE.md"                    "Claude Code import of AGENTS.md"
check_file ".cursor/rules/00-project-overview.mdc" "Cursor project overview"
check_file ".continue/config.yaml"        "Continue config"

if [ "$MISSING_CONFIG" = true ]; then
  warn "Some AI config files are missing. Run: bash .initium/scripts/validate.sh"
fi

# ---------------------------------------------------------------------------
# 5. Remind about customization
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Next Steps"
echo "========================================"
echo ""
echo "  STEP 1 — Run the initialization wizard:"
echo "  bash .initium/scripts/init.sh"
echo "  (configures project name, stack, tracker, and domain keywords)"
echo ""
echo "  STEP 2 — AI-powered content generation:"
echo "  Open Claude Code and run:  /init <describe your project>"
echo "  Or in Cursor:              @.cursor/prompts/init.md"
echo ""
echo "  This populates:"
echo "    * AGENTS.md, docs/context/, docs/architecture/overview.md"
echo "    * agent.config.yaml domain keywords"
echo "    * .github/workflows/ci.yml  (use: /init ci: <your stack>)"
echo ""
echo "  STEP 3 — Finish setup:"
echo "  * Edit .continue/config.yaml (add API keys)"
echo "  * Add git remote:  git remote add origin <url>"
echo "  * Install dependencies: [from AGENTS.md after /init]"
echo "  * Validate: bash .initium/scripts/validate.sh"
echo "  * Read the AI workflow: docs/guides/ai-workflow.md"
echo ""
echo "  AI commands available in Claude Code (type / to invoke):"
echo "  /init       — populate all TODO files from your project description"
echo "  /architect  — design a feature before implementing"
echo "  /review     — review code for issues"
echo "  /test       — generate tests"
echo "  /debug      — systematic debugging"
echo ""

success "Setup complete!"
