# Containerized Agent — Setup Guide

Run the Initium autonomous agent as a long-lived Docker container. The image bakes in the full Initium runtime (slash commands, hooks, rules); your project source code is never bundled — it is cloned from `GIT_REPO_URL` at container startup.

Two trigger modes are available — use one or both:

| Mode | Service | How it works |
|------|---------|--------------|
| **Polling** | `agent` | Always runs cron on `GROOM_CRON` schedule |
| **Event-driven** | `webhook` | Starts webhook receiver if `JIRA_WEBHOOK_SECRET` is set; **falls back to cron polling automatically** if not |

Both services are self-contained — each clones the repository and overlays Initium tooling independently. Running them together is safe: the webhook service handles real-time events while the agent service acts as a catch-up sweep for anything missed.

---

## How It Works

```
Container startup
  │
  ├─ 1. Validate required env vars (AI provider + GIT_REPO_URL)
  ├─ 2. Configure git identity and credential helper
  ├─ 3. Clone GIT_REPO_URL → /workspace  (or git pull if already cloned)
  ├─ 4. Overlay Initium tooling if absent in the workspace:
  │      .claude/ · .cursor/ · .continue/ · .opencode/ · opencode.json · agent.config.yaml
  ├─ 5. Export env vars to /etc/environment (so cron jobs can read them)
  ├─ 6. Write /etc/cron.d/initium-agent with GROOM_CRON schedule
  └─ 7. Start cron daemon · tail /var/log/groom.log
              │
              └─ On each cron tick:
                   ├─ Check /workspace/.agent/STOP kill switch
                   ├─ git fetch + rebase onto origin/<branch>
                   │    (if the rebase fails: git reset --hard origin/<branch>)
                   ├─ Run /groom via $AGENT_CLI (default: claude --dangerously-skip-permissions -p "/groom")
                   └─ git push (if agent created commits)
```

> Local commits that cannot be rebased are discarded by the `reset --hard` fallback — the agent
> should deliver work through PR branches, not by committing to `GIT_BRANCH`.

**Tooling overlay** — if `.claude/`, `.cursor/`, `.continue/`, `.opencode/`, `opencode.json`, or `agent.config.yaml` already exist in the cloned repo (i.e., the project was initialized with `/init`), they are used as-is. The image copy is applied only when the directory or file is absent.

---

## Quick Start

### Polling only (cron-based)

```bash
cp .initium/docker/.env.example .initium/docker/.env
$EDITOR .initium/docker/.env   # fill in GIT_REPO_URL, AI provider, JIRA creds

docker compose -f .initium/docker/docker-compose.yml up -d --build agent
docker logs -f initium-agent
```

### Polling + webhook receiver

```bash
cp .initium/docker/.env.example .initium/docker/.env
$EDITOR .initium/docker/.env   # also set JIRA_WEBHOOK_SECRET

docker compose -f .initium/docker/docker-compose.yml up -d --build
docker logs -f initium-agent    # cron runner
docker logs -f initium-webhook  # webhook receiver

# Point your Jira Server / Data Center webhook at:
#   http://<host>:3001/jira-webhook
# Every request must carry X-Jira-Secret: <JIRA_WEBHOOK_SECRET>. Jira's webhook UI cannot add
# custom headers — inject it with a reverse proxy (see jira-server-setup.md § 9.3).
```

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `GIT_REPO_URL` | Full HTTPS clone URL of the repo to work on. For private repos embed the token: `https://x-token:<GITHUB_TOKEN>@github.com/org/repo.git` |
| One AI provider group (see below) | Credentials for the AI backend |

### AI CLI

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_CLI` | `claude` | Which CLI executes the agent workflows. See table below. |

| Value | CLI | How /groom is invoked | Reads rules from |
|-------|-----|-----------------------|-----------------|
| `claude` | Claude Code | `claude --dangerously-skip-permissions -p "/groom"` | `.claude/commands/` |
| `cursor` | Cursor CLI | `cursor --print --force "$(cat .claude/commands/groom.md)"` | `.cursor/rules/` |
| `opencode` | OpenCode CLI | `opencode run "/groom"` | `.opencode/commands/` + `opencode.json` |

> Claude Code and Cursor CLI are installed in the default image. OpenCode is supported when the `opencode` binary is available (custom image or host install). Switch with `AGENT_CLI` — no rebuild required for claude/cursor.

### AI Provider — choose one

**Option A: Anthropic (direct)**

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key (`sk-ant-…`) |

**Option B: AWS Bedrock**

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_USE_BEDROCK` | Set to `1` |
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret |
| `AWS_SESSION_TOKEN` | Only if using temporary credentials |
| `AWS_REGION` | e.g. `us-east-1` |

**Option C: Google Vertex AI**

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_USE_VERTEX` | Set to `1` |
| `CLOUD_ML_REGION` | e.g. `us-east5` |
| `ANTHROPIC_VERTEX_PROJECT_ID` | Your GCP project ID |

For Vertex, mount your service account JSON via the `volumes` section in `docker-compose.yml`:
```yaml
volumes:
  - /path/to/gcp-key.json:/run/secrets/gcp-key.json:ro
```
And set `GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/gcp-key.json` in the environment.

### Issue Tracker

| Variable | Description |
|----------|-------------|
| `JIRA_URL` | e.g. `https://yourcompany.atlassian.net` (Cloud) or `https://jira.yourcompany.com` (Data Center / Server) |
| `JIRA_EMAIL` | Atlassian account email (Cloud) — the login **username** on Data Center / Server |
| `JIRA_API_TOKEN` | Jira API token (Cloud) or Personal Access Token (Data Center / Server 8.14+) |
| `LINEAR_API_KEY` | Linear API key (alternative to JIRA) |

### Git Hosting

| Variable | Description |
|----------|-------------|
| `GITHUB_TOKEN` | Fine-grained personal access token or GitHub App token (Contents + Pull requests: read/write) — used for PR creation and HTTPS git auth |
| `GITLAB_TOKEN` | GitLab personal access token (alternative to GitHub) |
| `GIT_BRANCH` | Branch to clone and push to (default: `main`) |
| `GIT_AUTHOR_NAME` | Commit author name (default: `Initium Agent`) |
| `GIT_AUTHOR_EMAIL` | Commit author email (default: `agent@noreply.local`) |
| `GIT_CLONE_DEPTH` | Shallow clone depth (default: `50`) |

### Notifications

| Variable | Description |
|----------|-------------|
| `SLACK_BOT_TOKEN` | Slack bot token for escalation notifications |
| `SLACK_TEAM_ID` | Slack workspace ID |

### Passthrough

| Variable | Description |
|----------|-------------|
| `CURSOR_API_KEY` | Cursor API key — authenticates the Cursor CLI when `AGENT_CLI=cursor`; otherwise passed through to workspace tooling that uses it. |

### Schedule (`agent` service)

| Variable | Default | Description |
|----------|---------|-------------|
| `GROOM_CRON` | `*/15 * * * *` | Standard cron expression controlling how often `/groom` runs. Matches `agent.config.yaml → issue_tracker.<provider>.poll_interval_minutes: 15`. |

**Schedule examples:**

```bash
GROOM_CRON=*/30 * * * *      # every 30 minutes
GROOM_CRON=0 9-17 * * 1-5   # hourly during business hours, weekdays
GROOM_CRON=0 8 * * 1         # once a week, Monday at 08:00
```

### Webhook (`webhook` service)

| Variable | Default | Description |
|----------|---------|-------------|
| `JIRA_WEBHOOK_SECRET` | _(unset)_ | Enables webhook mode. Shared secret expected in the `X-Jira-Secret` header. When empty, the `webhook` service falls back to cron polling. Generate: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` |
| `WEBHOOK_PORT` | `3001` | Port the receiver listens on (also the published host port) |
| `WEBHOOK_PATH` | `/jira-webhook` | URL path Jira posts to |
| `JIRA_SERVER_IP` | _(unset)_ | Comma-separated IP allowlist. When unset, any IP is accepted (secret-only validation). |

---

## Volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `workspace` | `/workspace` | Cloned project repository, shared by both services — persisted across restarts so the container resumes without re-cloning. Agent runs execute here, so task state, decision audit logs, outputs, and the kill switch live in `/workspace/.agent/` |
| `agent-state` | `/initium/.agent` | `.agent/` of the baked Initium runtime. The webhook receiver runs from `/initium`, so its `<date>-webhooks.jsonl` log lands in `/initium/.agent/audit/` |

---

## Webhook Receiver Architecture

The `webhook` service copies `/initium/.agent-templates/webhook-receiver.mjs` to `/workspace/.agent/webhook-receiver.mjs` on first run (an existing copy is kept, so you can customise it) and listens for Jira POST events:

```
Jira Server / Data Center
  │  POST /jira-webhook
  │  X-Jira-Secret: <secret>   (injected by a reverse proxy)
  ▼
webhook container (port 3001)
  ├─ Path + method check (404 otherwise)
  ├─ IP allowlist check  (JIRA_SERVER_IP → 403)
  ├─ Secret validation   (timing-safe compare → 401)
  ├─ Body ≤ 1 MB, valid JSON (413 / 400)
  ├─ ACK 200 immediately (Jira expects fast response)
  └─ Handle async:
       jira:issue_created / jira:issue_updated
         → skip if labelled agent-accepted / agent-in-progress / agent-done / agent-rejected
         → claude -p "/triage <issue-key>"

       comment_created whose first word is an allow-listed AGENT_* command
         → claude -p "/loop resume <issue-key> <command> [phase=<phase>]"
           (AGENT_RESUME, AGENT_APPROVE_DESIGN, AGENT_APPROVE_DEPLOY, AGENT_ABANDON,
            AGENT_REASSIGN, AGENT_SKIP_TASK, AGENT_REJECT)
```

> The receiver starts `claude` with `execFile` — no shell — and passes only a validated issue key
> (`PROJ-123`), the allow-listed command token, and a `phase` matching `[a-z_]+`. The issue summary
> and the rest of the comment are never part of the prompt; `/triage` and `/loop` read the ticket
> themselves. Invalid keys or phases are logged and dropped. Set `CLAUDE_BIN` to use another binary
> path. The receiver ignores `AGENT_CLI` and does not handle `AGENT_CLARIFY` — answer clarifications
> on the GitHub escalation issue, which `/escalate` polls.

**Jira webhook configuration** — in Jira administration (**System → WebHooks**):
- URL: `http://<docker-host>:3001/jira-webhook` (or the TLS proxy URL in front of it)
- Events: Issue `created`, `updated`; Comment `created`
- Shared secret: Jira's webhook form cannot send the `X-Jira-Secret` header, so inject it with a
  reverse proxy. Jira Data Center 10+ can also sign payloads (`X-Hub-Signature`, HMAC-SHA256),
  but the stock receiver does not verify that signature.

For full Jira Server / Data Center admin setup see [jira-server-setup.md](jira-server-setup.md).

> **Production note:** Put a TLS-terminating reverse proxy (nginx, Caddy) in front of the webhook port. Never expose port 3001 directly to the internet without TLS.

---

## Polling vs. Webhook — When to use each

| | Polling (`agent`) | Webhook (`webhook`) |
|---|---|---|
| **Trigger** | Time-based (cron) | Event-based (Jira push) |
| **Latency** | Up to `GROOM_CRON` interval | Near-instant |
| **Works with** | Jira Cloud, Data Center, Server; Linear; GitHub Issues | Jira Data Center / Server (Cloud cannot send the `X-Jira-Secret` header — use polling) |
| **Network requirement** | Outbound only | Jira must reach the container |
| **Fallback** | — | Cron polling if `JIRA_WEBHOOK_SECRET` unset |
| **Complexity** | Minimal | Requires exposed port + TLS in prod |

### Decision guide

```
Is JIRA_WEBHOOK_SECRET configured?
  No  → webhook service falls back to cron (same as agent service; logs a warning)
  Yes → Is Jira able to reach the container?
          No  → events never arrive and the receiver cannot detect it —
                run the agent service for polling
          Yes → event-driven mode active; run agent alongside for catch-up
```

---

## Operations

### Stopping and resuming

```bash
# Stop (state is preserved in volumes)
docker compose -f .initium/docker/docker-compose.yml stop

# Resume
docker compose -f .initium/docker/docker-compose.yml start
```

### Emergency kill switch

Create `.agent/STOP` inside the workspace to halt the agent without stopping the container. The runner script checks for this file before every `/groom` invocation.

```bash
# Halt agent runs
docker exec initium-agent touch /workspace/.agent/STOP

# Re-enable
docker exec initium-agent rm /workspace/.agent/STOP
```

### Viewing logs

```bash
# Live agent log (groom runs)
docker logs -f initium-agent

# Audit trail (one JSON line per agent decision)
docker exec initium-agent cat /workspace/.agent/audit/$(date +%Y-%m-%d)-decisions.jsonl
```

### Forcing an immediate groom run

```bash
docker exec initium-agent /groom-runner.sh
```

### Viewing webhook logs

```bash
docker logs -f initium-webhook

# Webhook audit trail (one JSON line per event; the receiver runs from /initium)
docker exec initium-webhook cat /initium/.agent/audit/$(date +%Y-%m-%d)-webhooks.jsonl
```

### Testing the webhook endpoint

```bash
# Send a synthetic issue_created event
curl -s -X POST http://localhost:3001/jira-webhook \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: <your-secret>" \
  -d '{
    "webhookEvent": "jira:issue_created",
    "issue": {
      "key": "PROJ-99",
      "fields": { "summary": "Test webhook delivery", "labels": [], "status": { "name": "To Do" } }
    }
  }'
# Expected: {"received":true,"issueKey":"PROJ-99","webhookEvent":"jira:issue_created"}
```

### Rebuilding after Initium updates

```bash
docker compose -f .initium/docker/docker-compose.yml build --no-cache
docker compose -f .initium/docker/docker-compose.yml up -d
```

---

## Security Notes

- **No secrets in the image.** All credentials are injected at runtime via environment variables — never baked into the image layer.
- **Pin the image inputs.** The Dockerfile builds `FROM node:22-slim` and installs the AI CLIs at their latest versions. For reproducible, reviewable builds pin the base image by digest (`node:24-slim@sha256:<digest>` — Node 24 is the Active LTS; Node 22 is in maintenance until April 2027) and pin CLI versions. See the [`devops-docker` skill](../../../.claude/skills/devops-docker/SKILL.md).
- **`--dangerously-skip-permissions`** is required for unattended operation. The Initium [guardrails](../guardrails.md) still run: both services set `INITIUM_AGENT_MODE=autonomous`, so secret reads, protected-path edits, `forbidden_commands`, force pushes, and oversized commits are denied rather than asked about. `/loop` spawns [subagents](subagents.md) per phase when the CLI exposes a Task tool; the parent remains the orchestrator. The entrypoints overlay `.initium/guardrails/` and `.githooks/` when the repository lacks them and set `core.hooksPath=.githooks` unless the project already uses another hooks path.
- **Private repos** — prefer the `GITHUB_TOKEN` / `GITLAB_TOKEN` credential helper configured by the entrypoint. A token embedded in `GIT_REPO_URL` is stored in `/workspace/.git/config` on the volume.
- **Webhook input is untrusted.** Issue summaries and comment bodies come from Jira users. Keep the receiver behind the IP allowlist and TLS proxy, and review `.agent/webhook-receiver.mjs` before exposing it.
- **GCP service account keys** — mount as a read-only volume secret, never set the key contents as an env var.

---

## Troubleshooting

**Container exits immediately**
Check that `GIT_REPO_URL` and at least one AI provider credential are set. The entrypoint validates these and exits with an error message if missing.

**"No .claude/commands found" warning at startup**
Expected for repos not yet initialized with Initium. The entrypoint overlays the defaults automatically — no action needed.

**`/groom` runs but JIRA returns no issues**
Verify `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` are correct, and that `agent.config.yaml → issue_tracker.jira.backlog_jql` matches issues in your project.

**Git push fails**
Ensure `GITHUB_TOKEN` has Contents read/write (fine-grained token or GitHub App), or `GITLAB_TOKEN` has `write_repository`; branch protection on `GIT_BRANCH` also blocks direct pushes.

**Cron never fires**
Check the cron syntax in `GROOM_CRON` — the field must be a valid 5-part cron expression. Run `docker exec initium-agent crontab -l` to verify what was registered.

**Webhook returns 401**
`X-Jira-Secret` header value does not match `JIRA_WEBHOOK_SECRET`. Verify both sides use the same string with no trailing whitespace.

**Webhook returns 403**
The source IP is not in `JIRA_SERVER_IP`. Add the Jira IP — or, behind a reverse proxy, the proxy's IP (the receiver sees the direct peer address) — or unset `JIRA_SERVER_IP` to rely on secret-only validation.

**`webhook` service runs cron instead of the receiver**
`JIRA_WEBHOOK_SECRET` is empty, so the service fell back to polling. Set it in `.initium/docker/.env` and recreate the container.

**`webhook` service exits immediately**
Same validation as the agent service: `GIT_REPO_URL` and one AI provider credential must be set. Check `docker logs initium-webhook`.

**Webhook service starts but no triage runs**
The issue may carry an `agent-accepted` / `agent-in-progress` / `agent-done` / `agent-rejected` label — the receiver skips those. Remove the label in Jira to re-trigger.

**Triage runs again on every issue update**
`/triage` labels issues `ai-agent-accepted` / `ai-agent-rejected` / `ai-agent-needs-triage`, which are not in the receiver's skip list. Add them to `skipLabels` in `.agent/webhook-receiver.mjs`, or filter the Jira webhook with JQL (`labels is EMPTY OR labels not in (ai-agent-accepted, ai-agent-rejected)`).
