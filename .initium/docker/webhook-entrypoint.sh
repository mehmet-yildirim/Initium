#!/usr/bin/env bash
# =============================================================================
# Initium Agent — Webhook Service Entrypoint
# =============================================================================
# Self-contained entrypoint that handles workspace setup and then picks the
# best available trigger method:
#
#   JIRA_WEBHOOK_SECRET set   → start Jira Server webhook receiver (event-driven)
#   JIRA_WEBHOOK_SECRET unset → fall back to cron polling (same as agent service)
#
# Running both services simultaneously is safe and recommended:
#   agent   — cron catch-up sweep (events that arrived while webhook was down)
#   webhook — instant real-time triage on Jira push
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[webhook]${NC} $*"; }
warn()  { echo -e "${YELLOW}[webhook]${NC} $*"; }
error() { echo -e "${RED}[webhook]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Validation — same requirements as the agent service
# ---------------------------------------------------------------------------
if [ -z "${GIT_REPO_URL:-}" ]; then
  error "GIT_REPO_URL is required."
  exit 1
fi

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
# Overlay Initium tooling if absent in the workspace
# ---------------------------------------------------------------------------
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
# Choose trigger method
# ---------------------------------------------------------------------------
if [ -n "${JIRA_WEBHOOK_SECRET:-}" ]; then
  # ── Webhook mode ─────────────────────────────────────────────────────────
  RECEIVER="/workspace/.agent/webhook-receiver.mjs"
  if [ ! -f "${RECEIVER}" ]; then
    info "Deploying webhook-receiver.mjs from template …"
    mkdir -p /workspace/.agent
    cp /initium/.agent-templates/webhook-receiver.mjs "${RECEIVER}"
  fi

  WEBHOOK_PORT="${WEBHOOK_PORT:-3001}"
  WEBHOOK_PATH="${WEBHOOK_PATH:-/jira-webhook}"
  info "Webhook mode: starting receiver on port ${WEBHOOK_PORT} at ${WEBHOOK_PATH} …"
  exec node "${RECEIVER}"

else
  # ── Cron fallback ─────────────────────────────────────────────────────────
  warn "JIRA_WEBHOOK_SECRET is not set — falling back to cron polling."
  warn "Set JIRA_WEBHOOK_SECRET to enable event-driven mode."

  GROOM_CRON="${GROOM_CRON:-*/15 * * * *}"
  info "Cron fallback: scheduling /groom with '${GROOM_CRON}' …"

  # Export env vars for cron jobs
  printenv | grep -E '^(ANTHROPIC|CLAUDE_CODE|AWS_|GOOGLE_|JIRA_|LINEAR_|GITHUB_|GITLAB_|SLACK_|CURSOR_|GIT_|GROOM_|AGENT_)' \
    | sed "s/'/'\\\\''/" \
    > /etc/environment

  cat > /etc/cron.d/initium-webhook-fallback <<EOF
# Initium Webhook — cron fallback (no JIRA_WEBHOOK_SECRET configured)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib/node_modules/.bin

${GROOM_CRON} root /groom-runner.sh >> /var/log/groom.log 2>&1
EOF
  chmod 0644 /etc/cron.d/initium-webhook-fallback

  touch /var/log/groom.log
  info "Starting cron daemon …"
  service cron start

  info "Cron fallback running. Tailing /var/log/groom.log …"
  exec tail -f /var/log/groom.log
fi
