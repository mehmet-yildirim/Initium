# syntax=docker/dockerfile:1
# =============================================================================
# Initium Agent Runtime
# =============================================================================
# Runs an AI CLI headlessly on a cron schedule, cloning and pushing to a
# target git repository autonomously. The Initium tooling (.claude/commands,
# hooks, agent.config.yaml) is baked into the image; your project source is
# never bundled — it is cloned at container startup from GIT_REPO_URL.
#
# Published (on git tag v*.*.*): ghcr.io/mehmet-yildirim/initium-agent
#
# Supported AI CLIs (select via AGENT_CLI env var, default: claude):
#   claude   — Claude Code CLI  (uses .claude/commands/ slash commands)
#   cursor   — Cursor CLI       (reads command file content as prompt)
#   opencode — OpenCode CLI     (uses .opencode/commands/ slash commands)
#
# Supported AI providers (set ONE group of env vars):
#   - Anthropic direct:  ANTHROPIC_API_KEY
#   - AWS Bedrock:       CLAUDE_CODE_USE_BEDROCK=1 + AWS_ACCESS_KEY_ID + ...
#   - Google Vertex AI:  CLAUDE_CODE_USE_VERTEX=1  + GOOGLE_APPLICATION_CREDENTIALS
# =============================================================================

FROM node:22-slim

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      cron \
      ca-certificates \
      curl \
      bash \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Claude Code CLI  (AGENT_CLI=claude, default)
# ---------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# ---------------------------------------------------------------------------
# Cursor CLI  (AGENT_CLI=cursor)
# Installs to ~/.cursor/bin/cursor; symlinked to /usr/local/bin for PATH access.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://cursor.com/install | bash \
    && ln -sf "${HOME}/.cursor/bin/cursor" /usr/local/bin/cursor

# ---------------------------------------------------------------------------
# Initium runtime layout
# ---------------------------------------------------------------------------
WORKDIR /initium

# Bake in all Initium runtime tooling and default agent config
COPY .claude/            .claude/
COPY .cursor/            .cursor/
COPY .continue/          .continue/
COPY .opencode/          .opencode/
COPY opencode.json       ./
COPY .agent-templates/   .agent-templates/
COPY agent.config.yaml   ./
COPY .initium/guardrails/ .initium/guardrails/
COPY .githooks/          .githooks/

# Entrypoints and runners
COPY .initium/docker/entrypoint.sh         /entrypoint.sh
COPY .initium/docker/groom-runner.sh       /groom-runner.sh
COPY .initium/docker/webhook-entrypoint.sh /webhook-entrypoint.sh
RUN chmod +x /entrypoint.sh /groom-runner.sh /webhook-entrypoint.sh

# Workspace is mounted or cloned at runtime — never baked in
VOLUME ["/workspace"]

# Persist agent state (audit logs, task state) across restarts
VOLUME ["/initium/.agent"]

ENTRYPOINT ["/entrypoint.sh"]
