#!/usr/bin/env bash
# =============================================================================
# Initium Agent — Container Entrypoint
# =============================================================================
# 1. Configures git identity
# 2. Clones (or updates) the target repository into /workspace
# 3. Overlays Initium tooling onto the workspace if not already present
# 4. Schedules the /groom cron job
# 5. Tails the log so the container stays alive and output is visible
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colours for legible startup output
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[initium]${NC} $*"; }
warn()  { echo -e "${YELLOW}[initium]${NC} $*"; }
error() { echo -e "${RED}[initium]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [ -z "${GIT_REPO_URL:-}" ]; then
  error "GIT_REPO_URL is required."
  exit 1
fi

# At least one AI provider credential must be set
if [ -z "${ANTHROPIC_API_KEY:-}" ] \
   && [ -z "${CLAUDE_CODE_USE_BEDROCK:-}" ] \
   && [ -z "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
  error "No AI provider credentials found."
  error "Set ANTHROPIC_API_KEY, or CLAUDE_CODE_USE_BEDROCK=1, or CLAUDE_CODE_USE_VERTEX=1."
  exit 1
fi

# ---------------------------------------------------------------------------
# Git identity
# ---------------------------------------------------------------------------
git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@noreply.local}"
git config --global user.name  "${GIT_AUTHOR_NAME:-Initium Agent}"
git config --global --add safe.directory /workspace

# Configure credential helper when a token is available
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper \
    "!f() { echo \"username=x-token\"; echo \"password=${GITHUB_TOKEN}\"; }; f"
fi
if [ -n "${GITLAB_TOKEN:-}" ]; then
  git config --global credential.helper \
    "!f() { echo \"username=oauth2\"; echo \"password=${GITLAB_TOKEN}\"; }; f"
fi

# ---------------------------------------------------------------------------
# Clone or refresh workspace
# ---------------------------------------------------------------------------
BRANCH="${GIT_BRANCH:-main}"

if [ -d "/workspace/.git" ]; then
  info "Workspace exists — pulling latest from origin/${BRANCH} …"
  git -C /workspace fetch origin
  git -C /workspace checkout "${BRANCH}" 2>/dev/null || true
  git -C /workspace reset --hard "origin/${BRANCH}"
else
  info "Cloning ${GIT_REPO_URL} (branch: ${BRANCH}) into /workspace …"
  git clone --branch "${BRANCH}" --depth "${GIT_CLONE_DEPTH:-50}" \
    "${GIT_REPO_URL}" /workspace
fi

# ---------------------------------------------------------------------------
# Overlay Initium tooling if the workspace was not initialised with Initium
# ---------------------------------------------------------------------------
# For each directory: copy from the baked image only if absent in the workspace.
# This preserves any customisations the project has already committed.
overlay() {
  local src="/initium/$1" dst="/workspace/$1"
  if [ ! -d "${dst}" ]; then
    info "Overlaying ${1} from Initium defaults …"
    mkdir -p "$(dirname "${dst}")"
    cp -rn "${src}" "${dst}" 2>/dev/null || true
  fi
}

overlay ".claude"
overlay ".cursor"
overlay ".continue"
overlay ".opencode"
overlay ".initium/guardrails"
overlay ".githooks"

# Guardrail pre-commit hook; a project-defined hooks path is kept but reported.
HOOKS_PATH="$(git -C /workspace config --get core.hooksPath || true)"
if [ -z "${HOOKS_PATH}" ]; then
  git -C /workspace config core.hooksPath .githooks
elif [ "${HOOKS_PATH}" != ".githooks" ]; then
  warn "core.hooksPath is '${HOOKS_PATH}' — call .githooks/pre-commit from it to keep guardrails."
fi

if [ ! -f "/workspace/opencode.json" ]; then
  info "Overlaying opencode.json from Initium defaults …"
  cp -n /initium/opencode.json /workspace/opencode.json 2>/dev/null || true
fi

if [ ! -f "/workspace/agent.config.yaml" ]; then
  info "Overlaying agent.config.yaml from Initium defaults …"
  cp -n /initium/agent.config.yaml /workspace/agent.config.yaml 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Cron schedule
# ---------------------------------------------------------------------------
# Default: every 15 minutes (matches agent.config.yaml poll_interval_minutes)
# Override via GROOM_CRON env var using standard cron syntax.
GROOM_CRON="${GROOM_CRON:-*/15 * * * *}"
info "Scheduling /groom: '${GROOM_CRON}'"

# Export all relevant env vars so cron jobs can read them
printenv | grep -E '^(ANTHROPIC|CLAUDE_CODE|AWS_|GOOGLE_|JIRA_|LINEAR_|GITHUB_|GITLAB_|SLACK_|CURSOR_|GIT_|GROOM_|AGENT_)' \
  | sed "s/'/'\\\\''/" \
  > /etc/environment

# Write crontab
cat > /etc/cron.d/initium-agent <<EOF
# Initium Agent — /groom schedule
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib/node_modules/.bin

${GROOM_CRON} root /groom-runner.sh >> /var/log/groom.log 2>&1
EOF
chmod 0644 /etc/cron.d/initium-agent

# ---------------------------------------------------------------------------
# Create log file and start cron daemon
# ---------------------------------------------------------------------------
touch /var/log/groom.log
info "Starting cron daemon …"
service cron start

info "Agent is running. Tailing /var/log/groom.log (Ctrl-C to stop) …"
exec tail -f /var/log/groom.log
