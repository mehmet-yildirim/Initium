#!/usr/bin/env bash
# =============================================================================
# Initium — Interactive Project Initialization Wizard
# =============================================================================
# Run this after setup.sh to configure your project's mechanical settings.
# This script handles structured inputs (name, tracker keys, stack choice).
# For AI-powered content generation (domain boundaries, architecture docs),
# run /init in Claude Code or @.cursor/prompts/init.md in Cursor afterwards.
#
# Usage:
#   bash .initium/scripts/init.sh                     # interactive mode
#   bash .initium/scripts/init.sh --non-interactive   # use env vars (for CI)
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
section() { echo -e "\n${BLUE}${BOLD}── $* ──────────────────────────────────────────${NC}"; }
prompt()  { echo -e "${BOLD}$*${NC}"; }

# ---------------------------------------------------------------------------
# Non-interactive mode: read from environment variables
# ---------------------------------------------------------------------------
NON_INTERACTIVE=false
if [[ "${1:-}" == "--non-interactive" ]]; then
  NON_INTERACTIVE=true
fi

ask() {
  local var_name="$1"
  local question="$2"
  local default="${3:-}"

  if [ "$NON_INTERACTIVE" = true ]; then
    # Use env var if set, otherwise use default
    local env_val="${!var_name:-}"
    if [ -n "$env_val" ]; then
      printf -v "$var_name" '%s' "$env_val"
      return
    elif [ -n "$default" ]; then
      printf -v "$var_name" '%s' "$default"
      return
    fi
    echo "ERROR: $var_name not set and no default available." >&2
    exit 1
  fi

  if [ -n "$default" ]; then
    prompt "$question [${default}]: "
  else
    prompt "$question: "
  fi
  read -r input
  if [ -z "$input" ] && [ -n "$default" ]; then
    printf -v "$var_name" '%s' "$default"
  elif [ -n "$input" ]; then
    printf -v "$var_name" '%s' "$input"
  else
    printf -v "$var_name" '%s' ""
  fi
}

ask_choice() {
  local var_name="$1"
  local question="$2"
  shift 2
  local options=("$@")

  if [ "$NON_INTERACTIVE" = true ]; then
    local env_val="${!var_name:-}"
    if [ -n "$env_val" ]; then
      printf -v "$var_name" '%s' "$env_val"
      return
    fi
    printf -v "$var_name" '%s' "${options[0]}"
    return
  fi

  echo ""
  prompt "$question"
  local i=1
  for opt in "${options[@]}"; do
    echo "  $i) $opt"
    ((i++))
  done
  prompt "Choice [1]: "
  read -r choice
  choice="${choice:-1}"
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
    printf -v "$var_name" '%s' "${options[$((choice-1))]}"
  else
    printf -v "$var_name" '%s' "${options[0]}"
  fi
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-\|-$//g'
}

# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  AI-Native Project Initialization Wizard"
echo "============================================================"
echo "  This wizard configures the mechanical project settings."
echo "  Run /init in Claude Code afterwards for AI-powered"
echo "  content generation (domain, architecture, CI steps)."
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
section "Project Identity"
# ---------------------------------------------------------------------------

ask PROJECT_NAME "Project name" ""
while [ -z "$PROJECT_NAME" ]; do
  warn "Project name cannot be empty."
  ask PROJECT_NAME "Project name" ""
done

PROJECT_SLUG=$(slugify "$PROJECT_NAME")

ask_choice PROJECT_TYPE "Project type" \
  "REST API" \
  "GraphQL API" \
  "Web App (full-stack)" \
  "Frontend (SPA)" \
  "CLI Tool" \
  "Library / SDK" \
  "Microservice" \
  "Mobile App" \
  "Other"

ask PROJECT_PURPOSE "One-sentence description (what it does and for whom)" ""

# ---------------------------------------------------------------------------
section "Technology Stack"
# ---------------------------------------------------------------------------

ask_choice PRIMARY_LANGUAGE "Primary language" \
  "TypeScript" \
  "Python" \
  "Go" \
  "Java" \
  ".NET / C#" \
  "Kotlin" \
  "Swift" \
  "Dart (Flutter)" \
  "Other"

case "$PRIMARY_LANGUAGE" in
  TypeScript)
    ask_choice FRAMEWORK "Framework" "Fastify" "Express" "NestJS" "Next.js" "Hono" "Other"
    ask_choice RUNTIME "Runtime" "Node.js 22" "Bun 1.x" "Deno" "Other"
    INSTALL_CMD="bun install"
    TEST_CMD="bun test"
    LINT_CMD="bun lint"
    BUILD_CMD="bun build"
    ;;
  Python)
    ask_choice FRAMEWORK "Framework" "FastAPI" "Django" "Flask" "None (scripts/library)" "Other"
    RUNTIME="Python 3.12"
    INSTALL_CMD="pip install -e '.[dev]'"
    TEST_CMD="pytest"
    LINT_CMD="ruff check ."
    BUILD_CMD="python -m build"
    ;;
  Go)
    FRAMEWORK="stdlib"
    ask_choice FRAMEWORK "Web framework (if applicable)" "None (stdlib)" "Gin" "Echo" "Fiber" "Chi"
    RUNTIME="Go 1.23"
    INSTALL_CMD="go mod tidy"
    TEST_CMD="go test ./..."
    LINT_CMD="golangci-lint run"
    BUILD_CMD="go build ./..."
    ;;
  Java)
    ask_choice FRAMEWORK "Framework" "Spring Boot 3" "Quarkus" "Micronaut" "Plain Java" "Other"
    RUNTIME="Java 21"
    INSTALL_CMD="mvn install -DskipTests"
    TEST_CMD="mvn test"
    LINT_CMD="mvn checkstyle:check"
    BUILD_CMD="mvn package"
    ;;
  ".NET / C#")
    ask_choice FRAMEWORK "Framework" "ASP.NET Core Minimal API" "ASP.NET Core MVC" "Other"
    RUNTIME=".NET 8"
    INSTALL_CMD="dotnet restore"
    TEST_CMD="dotnet test"
    LINT_CMD="dotnet format --verify-no-changes"
    BUILD_CMD="dotnet build"
    ;;
  *)
    ask FRAMEWORK "Framework (leave blank if none)" ""
    ask RUNTIME "Runtime / version" ""
    ask INSTALL_CMD "Install command" ""
    ask TEST_CMD "Test command" ""
    ask LINT_CMD "Lint command" ""
    ask BUILD_CMD "Build command" ""
    ;;
esac

ask_choice DATABASE "Database" \
  "PostgreSQL" \
  "MySQL / MariaDB" \
  "MongoDB" \
  "SQLite" \
  "Redis (primary)" \
  "None" \
  "Other"

# ---------------------------------------------------------------------------
section "Issue Tracker"
# ---------------------------------------------------------------------------

ask_choice TRACKER "Issue tracker" "GitHub Issues" "JIRA (cloud)" "JIRA (server / on-prem)" "Linear" "None"

JIRA_URL=""
JIRA_PROJECT_KEY=""
LINEAR_TEAM_ID=""
GITHUB_OWNER=""
GITHUB_REPO=""

case "$TRACKER" in
  "GitHub Issues")
    ask GITHUB_OWNER "GitHub organization or username" ""
    ask GITHUB_REPO "GitHub repository name" "$PROJECT_SLUG"
    TRACKER_PROVIDER="github"
    ;;
  JIRA*)
    ask JIRA_URL "JIRA base URL (e.g. https://mycompany.atlassian.net)" ""
    ask JIRA_PROJECT_KEY "JIRA project key (e.g. PROJ)" ""
    ask GITHUB_OWNER "GitHub organization (for PR/escalation)" ""
    ask GITHUB_REPO "GitHub repository name" "$PROJECT_SLUG"
    TRACKER_PROVIDER="jira"
    ;;
  Linear)
    ask LINEAR_TEAM_ID "Linear team ID" ""
    ask GITHUB_OWNER "GitHub organization (for PR/escalation)" ""
    ask GITHUB_REPO "GitHub repository name" "$PROJECT_SLUG"
    TRACKER_PROVIDER="linear"
    ;;
  None)
    TRACKER_PROVIDER="github"
    ask GITHUB_OWNER "GitHub organization (used for PRs and escalations)" ""
    ask GITHUB_REPO "GitHub repository name" "$PROJECT_SLUG"
    ;;
esac

# ---------------------------------------------------------------------------
section "Escalation & Alerts"
# ---------------------------------------------------------------------------

ask_choice ESCALATION_CHANNEL "Primary escalation channel" "Slack" "Email" "GitHub Issues only" "PagerDuty"

SLACK_CHANNEL=""
ESCALATION_EMAIL=""
case "$ESCALATION_CHANNEL" in
  Slack)
    ask SLACK_CHANNEL "Slack channel name (e.g. #dev-alerts)" "#dev-alerts"
    ;;
  Email)
    ask ESCALATION_EMAIL "Escalation email address" ""
    ;;
esac

# ---------------------------------------------------------------------------
section "Domain Keywords"
# ---------------------------------------------------------------------------

echo ""
info "Domain keywords help the autonomous agent classify issues correctly."
info "Enter comma-separated keywords or leave blank to fill in later."
echo ""

ask INCLUDE_KEYWORDS "In-domain keywords (nouns/verbs for your system's core concepts)" ""
ask EXCLUDE_KEYWORDS "Out-of-scope keywords (adjacent systems this project does NOT own)" ""

# ---------------------------------------------------------------------------
# Write configuration
# ---------------------------------------------------------------------------

section "Applying Configuration"

# --- agent.config.yaml ---
if [ -f "agent.config.yaml" ]; then
  info "Updating agent.config.yaml..."

  # Project identity
  sed -i.bak \
    -e "s|id: \"TODO: my-project-agent\"|id: \"${PROJECT_SLUG}-agent\"|g" \
    -e "s|name: \"TODO: My Project Dev Agent\"|name: \"${PROJECT_NAME} Dev Agent\"|g" \
    agent.config.yaml

  # Issue tracker provider
  sed -i.bak "s|provider: jira|provider: ${TRACKER_PROVIDER}|g" agent.config.yaml

  # JIRA settings
  if [ -n "$JIRA_PROJECT_KEY" ]; then
    sed -i.bak \
      -e "s|project_key: \"TODO\"|project_key: \"${JIRA_PROJECT_KEY}\"|g" \
      -e "s|project = \"TODO\"|project = \"${JIRA_PROJECT_KEY}\"|g" \
      agent.config.yaml
  fi
  if [ -n "$JIRA_URL" ]; then
    sed -i.bak "s|\${JIRA_URL}|${JIRA_URL}|g" agent.config.yaml
  fi

  # Linear
  if [ -n "$LINEAR_TEAM_ID" ]; then
    sed -i.bak "s|team_id: \"TODO\"|team_id: \"${LINEAR_TEAM_ID}\"|g" agent.config.yaml
  fi

  # GitHub
  if [ -n "$GITHUB_OWNER" ]; then
    sed -i.bak "s|owner: \"TODO\"|owner: \"${GITHUB_OWNER}\"|g" agent.config.yaml
  fi
  if [ -n "$GITHUB_REPO" ]; then
    sed -i.bak "s|repo: \"TODO\"|repo: \"${GITHUB_REPO}\"|g" agent.config.yaml
  fi

  # Domain keywords
  if [ -n "$INCLUDE_KEYWORDS" ]; then
    # Convert comma-separated to YAML array format
    YAML_INCLUDE=$(echo "$INCLUDE_KEYWORDS" | sed 's/,\s*/", "/g' | sed 's/^/"/' | sed 's/$/"/')
    sed -i.bak "s|strong_include_keywords: \[\]|strong_include_keywords: [${YAML_INCLUDE}]|g" agent.config.yaml
  fi
  if [ -n "$EXCLUDE_KEYWORDS" ]; then
    YAML_EXCLUDE=$(echo "$EXCLUDE_KEYWORDS" | sed 's/,\s*/", "/g' | sed 's/^/"/' | sed 's/$/"/')
    sed -i.bak "s|hard_exclude_keywords: \[\]|hard_exclude_keywords: [${YAML_EXCLUDE}]|g" agent.config.yaml
  fi

  # Escalation channel
  case "$ESCALATION_CHANNEL" in
    Slack)
      sed -i.bak "s|primary_channel: slack.*|primary_channel: slack|g" agent.config.yaml
      if [ -n "$SLACK_CHANNEL" ]; then
        sed -i.bak "s|channel: \"#dev-agent-alerts\"|channel: \"${SLACK_CHANNEL}\"|g" agent.config.yaml
      fi
      ;;
    Email)
      sed -i.bak "s|primary_channel: slack|primary_channel: email|g" agent.config.yaml
      ;;
    "GitHub Issues only")
      sed -i.bak "s|primary_channel: slack|primary_channel: github-issue|g" agent.config.yaml
      ;;
  esac

  if [ -n "$ESCALATION_EMAIL" ]; then
    sed -i.bak "s|to: \[\]  # TODO: \[\"dev-lead@company.com\"\]|to: [\"${ESCALATION_EMAIL}\"]|g" agent.config.yaml
  fi

  if [ -n "$GITHUB_OWNER" ]; then
    sed -i.bak "s|assignees: \[\]  # TODO: \[\"username\"\]|assignees: [\"${GITHUB_OWNER}\"]|g" agent.config.yaml
  fi

  rm -f agent.config.yaml.bak
  success "agent.config.yaml updated."
else
  warn "agent.config.yaml not found — skipping."
fi

# --- AGENTS.md — update project name, type, purpose, commands ---
if [ -f "AGENTS.md" ]; then
  info "Updating AGENTS.md..."
  sed -i.bak \
    -e "s|TODO: Project Name|${PROJECT_NAME}|g" \
    -e "s|TODO: e.g., REST API / Web App / CLI Tool / Library|${PROJECT_TYPE}|g" \
    -e "s|TODO: One or two sentences describing what this project does and for whom\.|${PROJECT_PURPOSE}|g" \
    -e "s|TODO: e.g., TypeScript, Python, Go|${PRIMARY_LANGUAGE}|g" \
    -e "s|TODO: e.g., bun install \/ pip install -e \"\.\[dev\]\" \/ go mod tidy|${INSTALL_CMD}|g" \
    -e "s|TODO: e.g., bun test \/ pytest \/ go test \.\.\.|${TEST_CMD}|g" \
    -e "s|TODO: e.g., bun lint \/ ruff check \. \/ golangci-lint run|${LINT_CMD}|g" \
    -e "s|TODO: e.g., bun build \/ python -m build \/ go build \.\.\.|${BUILD_CMD}|g" \
    AGENTS.md
  if [ -n "${FRAMEWORK:-}" ]; then
    sed -i.bak "s|TODO: e.g., Next.js 14, FastAPI, Gin|${FRAMEWORK}|g" AGENTS.md
  fi
  if [ -n "${RUNTIME:-}" ]; then
    sed -i.bak "s|TODO: e.g., Node.js 22, Python 3.12, Go 1.23|${RUNTIME}|g" AGENTS.md
  fi
  rm -f AGENTS.md.bak
  success "AGENTS.md updated."
fi

# --- .cursor/rules/00-project-overview.mdc ---
if [ -f ".cursor/rules/00-project-overview.mdc" ]; then
  info "Updating .cursor/rules/00-project-overview.mdc..."
  sed -i.bak \
    -e "s|TODO: Project Name|${PROJECT_NAME}|g" \
    -e "s|TODO: e.g., SaaS web app \/ internal tool \/ open-source library \/ CLI|${PROJECT_TYPE}|g" \
    .cursor/rules/00-project-overview.mdc
  if [ -n "${PROJECT_PURPOSE:-}" ]; then
    sed -i.bak "s|TODO: Describe what the project does and who uses it.*|${PROJECT_PURPOSE}|g" \
      .cursor/rules/00-project-overview.mdc
  fi
  rm -f .cursor/rules/00-project-overview.mdc.bak
  success ".cursor/rules/00-project-overview.mdc updated."
fi

# --- Write .project-config.yaml for AI tools to reference ---
info "Writing .project-config.yaml..."
cat > .project-config.yaml << YAML
# =============================================================================
# .project-config.yaml — Machine-readable project configuration
# Generated by .initium/scripts/init.sh — do not edit manually; re-run init.sh to update
# =============================================================================
project:
  name: "${PROJECT_NAME}"
  slug: "${PROJECT_SLUG}"
  type: "${PROJECT_TYPE}"
  purpose: "${PROJECT_PURPOSE}"

stack:
  language: "${PRIMARY_LANGUAGE}"
  framework: "${FRAMEWORK:-}"
  runtime: "${RUNTIME:-}"
  database: "${DATABASE}"
  commands:
    install: "${INSTALL_CMD}"
    test: "${TEST_CMD}"
    lint: "${LINT_CMD}"
    build: "${BUILD_CMD}"

tracker:
  provider: "${TRACKER_PROVIDER}"
  jira_url: "${JIRA_URL}"
  jira_project_key: "${JIRA_PROJECT_KEY}"
  linear_team_id: "${LINEAR_TEAM_ID}"
  github_owner: "${GITHUB_OWNER}"
  github_repo: "${GITHUB_REPO}"

domain:
  include_keywords: "${INCLUDE_KEYWORDS}"
  exclude_keywords: "${EXCLUDE_KEYWORDS}"

escalation:
  channel: "${ESCALATION_CHANNEL}"
  slack_channel: "${SLACK_CHANNEL}"
  email: "${ESCALATION_EMAIL}"
YAML
success ".project-config.yaml written."

# ---------------------------------------------------------------------------
section "Summary"
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}${BOLD}Project configured: ${PROJECT_NAME}${NC}"
echo ""
echo "  Updated files:"
echo "    ✅ agent.config.yaml"
echo "    ✅ AGENTS.md"
echo "    ✅ .cursor/rules/00-project-overview.mdc"
echo "    ✅ .project-config.yaml (reference for AI tools)"
echo ""
echo "  Not yet populated (run AI command below):"
echo "    ⚠️  docs/context/project-brief.md"
echo "    ⚠️  docs/context/domain-boundaries.md  ← critical for autonomous agent"
echo "    ⚠️  docs/context/domain-glossary.md"
echo "    ⚠️  docs/context/tech-stack.md"
echo "    ⚠️  docs/architecture/overview.md"
echo "    ⚠️  .github/workflows/ci.yml"
echo ""
echo -e "${CYAN}${BOLD}Next step — AI-powered initialization:${NC}"
echo ""
echo "  In Claude Code:   /init ${PROJECT_NAME} — ${PROJECT_PURPOSE}"
echo "  In Cursor:        @.cursor/prompts/init.md"
echo "                    (then describe your project in the message)"
echo ""
echo "  Or target specific sections:"
echo "  /init domain: <describe what your system manages and for whom>"
echo "  /init stack: ${PRIMARY_LANGUAGE}, ${FRAMEWORK:-no framework}, ${DATABASE}"
echo "  /init ci: <describe your deployment target and pipeline>"
echo ""
echo -e "${CYAN}Then validate: bash .initium/scripts/validate.sh${NC}"
echo ""
