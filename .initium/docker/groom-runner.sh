#!/usr/bin/env bash
# =============================================================================
# Initium Agent — Groom Runner
# =============================================================================
# Invoked by cron on each scheduled tick. Pulls the latest code, dispatches
# the /groom workflow via the configured AI CLI, then pushes any committed work.
#
# AGENT_CLI controls which CLI is used (default: claude):
#   claude — Claude Code: invokes the /groom slash command directly
#   cursor — Cursor CLI:  reads .claude/commands/groom.md and passes it as a
#            prompt (Cursor does not understand .claude/ slash commands)
#   opencode — OpenCode CLI: uses .opencode/commands/ (mirrored from .claude/)
# =============================================================================
set -euo pipefail

# Load env vars written by entrypoint (needed inside cron's minimal env)
set -a
# shellcheck source=/dev/null
[ -f /etc/environment ] && source /etc/environment
set +a

# Unattended run: guardrails (.initium/guardrails/) deny whatever they would ask about.
export INITIUM_AGENT_MODE=autonomous

LOG_PREFIX="[$(date '+%Y-%m-%dT%H:%M:%S')] [groom-runner]"

echo "${LOG_PREFIX} ── Run start ────────────────────────────────────────────"

# ---------------------------------------------------------------------------
# Kill-switch check
# ---------------------------------------------------------------------------
if [ -f "/workspace/.agent/STOP" ]; then
  echo "${LOG_PREFIX} STOP file detected — skipping run."
  exit 0
fi

# ---------------------------------------------------------------------------
# Pull latest changes before grooming
# ---------------------------------------------------------------------------
BRANCH="${GIT_BRANCH:-main}"
echo "${LOG_PREFIX} Pulling origin/${BRANCH} …"
git -C /workspace fetch origin
git -C /workspace rebase "origin/${BRANCH}" 2>/dev/null \
  || git -C /workspace reset --hard "origin/${BRANCH}"

# ---------------------------------------------------------------------------
# Dispatch groom workflow via configured AI CLI
# ---------------------------------------------------------------------------
AGENT_CLI="${AGENT_CLI:-claude}"
COMMAND_FILE="/workspace/.claude/commands/groom.md"

echo "${LOG_PREFIX} Invoking /groom via '${AGENT_CLI}' …"
cd /workspace

case "${AGENT_CLI}" in

  claude)
    # Claude Code understands .claude/commands/ slash commands natively.
    # --dangerously-skip-permissions is required for unattended container runs;
    # blast radius is constrained by agent.config.yaml and .claude/settings.json.
    claude \
      --dangerously-skip-permissions \
      -p "/groom" \
      2>&1
    ;;

  cursor)
    # Cursor CLI does not read .claude/commands/; pass the groom workflow
    # content directly as a prompt so Cursor executes it with .cursor/rules/ context.
    if [ ! -f "${COMMAND_FILE}" ]; then
      echo "${LOG_PREFIX} ERROR: ${COMMAND_FILE} not found — cannot build Cursor prompt."
      exit 1
    fi
    GROOM_PROMPT="$(cat "${COMMAND_FILE}")"
    cursor \
      --print \
      --force \
      "${GROOM_PROMPT}" \
      2>&1
    ;;

  opencode)
    if ! command -v opencode >/dev/null 2>&1; then
      echo "${LOG_PREFIX} ERROR: opencode CLI not found. Install OpenCode or set AGENT_CLI=claude."
      exit 1
    fi
    # OpenCode loads project commands from .opencode/commands/ and opencode.json.
    opencode run "/groom" 2>&1
    ;;

  *)
    echo "${LOG_PREFIX} ERROR: Unknown AGENT_CLI '${AGENT_CLI}'. Supported: claude, cursor, opencode"
    exit 1
    ;;

esac

EXIT_CODE=$?
echo "${LOG_PREFIX} /groom (${AGENT_CLI}) exited with code ${EXIT_CODE}"

# ---------------------------------------------------------------------------
# Push any commits the agent created
# ---------------------------------------------------------------------------
PENDING=$(git -C /workspace log "origin/${BRANCH}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "${PENDING}" -gt 0 ]; then
  echo "${LOG_PREFIX} Pushing ${PENDING} new commit(s) to origin/${BRANCH} …"
  git -C /workspace push origin "${BRANCH}"
else
  echo "${LOG_PREFIX} No new commits to push."
fi

echo "${LOG_PREFIX} ── Run complete ──────────────────────────────────────────"
exit "${EXIT_CODE}"
