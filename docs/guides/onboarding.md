# Developer Onboarding Guide

Welcome to the project. This guide gets you from zero to productive as quickly as possible.

> **Turkish / Türkçe:** [docs/guides/onboarding.tr.md](onboarding.tr.md) — Türkçe başlangıç kılavuzu

---

## Prerequisites

Before you start:

- [ ] TODO: List required tools (e.g., Node.js 22+, Docker, Git, etc.)
- [ ] TODO: Access to required services (e.g., AWS account, database, secrets)
- [ ] Git configured with your work email: `git config --global user.email "you@company.com"`
- [ ] An AI coding tool: [Cursor](https://cursor.com), [VS Code + Continue](https://continue.dev), [Claude Code](https://claude.ai/code), or [OpenCode](https://opencode.ai)

---

## Initial Setup

> **Adding Initium to a repository that already has code?** Don't clone Initium — follow
> [existing-project.md](existing-project.md), then continue from
> [Setting Up AI Tools](#setting-up-ai-tools).

### macOS / Linux

```bash
# 1. Clone
git clone <repo-url>
cd <project-name>

# 2. Initialize (git, .env, config checks)
./.initium/scripts/setup.sh

# 3. Run interactive wizard — fills project name, stack, tracker keys
bash .initium/scripts/init.sh

# 4. Let AI populate all remaining TODO files
claude
/init I'm building a <type> called <name> for <users>. Stack: <language, framework, DB>.

# 5. Verify everything is in place
bash .initium/scripts/validate.sh   # expect: all PASS, no FAIL
```

### Windows (PowerShell — recommended)

```powershell
# One-time: allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.\.initium\scripts\setup.ps1
.\.initium\scripts\init.ps1
# Then open Claude Code and run /init as above
.\.initium\scripts\validate.ps1
```

### Windows (Batch — no permissions needed)

```bat
.initium\scripts\setup.cmd
.initium\scripts\init.cmd
.initium\scripts\validate.cmd
```

### After the wizard — fill in manually

```bash
cp .env.example .env      # fill in credentials and API keys

# TODO: start local dependencies
# e.g., docker compose up -d

# TODO: install application dependencies
# e.g., bun install / pip install -e ".[dev]" / go mod tidy

# TODO: run database migrations
# e.g., bun db:migrate / alembic upgrade head

# TODO: verify the app works
# e.g., bun test / bun dev → open http://localhost:3000
```

---

## Understanding the Project

Read these documents in order before writing any code:

| Document | Contents |
|----------|---------|
| `docs/context/project-brief.md` | What this project does and for whom |
| `docs/context/tech-stack.md` | Technology choices and rationale |
| `docs/architecture/overview.md` | How the system is structured |
| `AGENTS.md` | Coding conventions, key commands, architecture summary |
| `docs/context/domain-glossary.md` | Business terminology — read before naming anything |
| `docs/context/domain-boundaries.md` | Scope definition (critical for autonomous agent) |
| `docs/guides/team.md` | Who owns what, escalation chain, decision authority |
| `docs/guides/team.tr.md` | Turkish / Türkçe version of the team guide |

---

## Setting Up AI Tools

> **Tip:** Once your AI tool is set up, `/help` is always your starting point when you don't know which command to use. Describe your situation and the AI will direct you.

### Claude Code

```bash
# Install (native installer — recommended; npm install is deprecated)
curl -fsSL https://claude.ai/install.sh | bash      # Windows PowerShell: irm https://claude.ai/install.ps1 | iex

# Launch — AGENTS.md is loaded automatically (CLAUDE.md imports it)
claude
```

All 40 custom commands (type `/` to see them; the same names work in Cursor and OpenCode):

```
# --- Help & setup (start here if you're unsure) ---
/help [question]  — show all commands, or map "how do I …?" to the right command sequence
/init             — populate all TODO files from a free-form project description
                    (scoped: /init domain: … | stack: … | ci: … | agent: …)
/sync-initium     — pull improvements from upstream Initium

# --- Planning & design ---
/requirements     — analyze requirements → user stories, tasks, DoD
/architect        — design before writing a single line of code
/task plan        — break design into tracked .agent/tasks/*.md files (one per PR)
/task next|list|status|done <id> — pick, track, and complete tasks
/sprint           — sprint planning: capacity, backlog, tasks, risk register

# --- Development ---
/implement        — structured bottom-up implementation with tests
/goal             — pursue one objective until its Definition of Done, no stopping mid-way
/refactor         — behavior-preserving refactor with a test safety net
/upgrade          — audit or upgrade dependencies, frameworks, runtimes
/debug            — systematic bug diagnosis: hypotheses → fix → prevention

# --- Quality & review ---
/test             — generate comprehensive tests
/qa               — full quality gates: lint, types, tests, coverage
/review           — code review against project standards and OWASP
/security-audit   — OWASP + CVE + secret scan (run before every PR)
/perf             — measure, find, and fix a performance bottleneck
/a11y             — accessibility audit and fixes (WCAG 2.2 AA)
/eval             — evaluation suites for LLM-powered features

# --- UI & visual design ---
/design           — design and build UI that looks deliberate, not templated
/design-review    — read-only UI review (template tells, craft, Apple HIG / Material 3)
/polish           — final visual quality pass before shipping
/design-system    — create or refresh DESIGN.md / PRODUCT.md and design tokens

# --- Context & knowledge ---
/codegraph        — code graph for symbol, caller, and impact lookups (saves tokens)
/skill            — create, update, or list Agent Skills in .claude/skills/

# --- Documentation ---
/docs             — code-level docs, architecture docs, user guides
/doc-api          — generate/update the OpenAPI spec
/doc-schema       — database ERD and table reference
/doc-diagrams     — Mermaid sequence diagrams for API and business flows
/doc-site         — scaffold or regenerate the documentation website
/doc-changelog    — generate CHANGELOG.md from git history

# --- Database, infrastructure, deployment ---
/migrate          — safe DB migration: Expand-Contract + rollback plan
/db               — database lifecycle: init, create, dml, seed, status, diff, audit
/infra            — scaffold Terraform / K8s / CI-CD for AWS, GCP, Azure, or on-prem
/deploy           — pre-deploy checklist + execution steps + monitoring plan

# --- Operations & autonomous agent ---
/standup          — daily summary from git history
/triage           — domain relevance check for a Jira/Linear/GitHub issue
/groom            — batch-process backlog through triage + requirements
/loop             — full autonomous loop: design → code → QA → PR → deploy
/escalate         — structured human notification when the agent is blocked
```

Full reference with arguments and modes: [`docs/guides/ai-workflow.md`](ai-workflow.md#all-commands--quick-reference).

### Cursor

1. Open the project folder in Cursor
2. Rules in `.cursor/rules/` load automatically by file type (no action needed)
3. Skills in `.claude/skills/` load on demand when a task or open file matches their description or `paths`
4. Slash commands from `.claude/commands/` work directly in Cursor — type `/` to see the full list
5. Enable MCP servers: edit `.cursor/mcp.json`, remove `"disabled": true`, set env vars in `.env`
6. Sign in to Cursor — a provider API key is only needed if you bring your own (Settings → Models)

### Continue (VS Code / JetBrains)

1. Install the Continue extension
2. Open `.continue/config.yaml` — it's auto-detected
3. Add your `ANTHROPIC_API_KEY` under the `models:` section
4. Uncomment the skill rules matching your stack (Java, Python, React, iOS, etc.)
5. Slash commands are available in the Continue chat panel

### OpenCode

1. Install [OpenCode](https://opencode.ai/docs/) and open this repo as the project directory
2. OpenCode reads `AGENTS.md` and `.claude/skills/` natively; `opencode.json` adds `.cursor/rules/` as instructions
3. All Initium slash commands live in `.opencode/commands/` (mirrors `.claude/commands/`)
4. In the TUI, run `/help`, `/goal`, `/implement`, etc. — same names as Claude Code and Cursor
5. After editing commands in `.claude/commands/`, refresh mirrors:

```bash
bash .initium/scripts/sync-opencode-commands.sh
```

---

## Development Workflow

```bash
# Start a feature
git checkout main && git pull
git checkout -b feat/PROJ-42-feature-name

# --- AI-assisted development loop ---
/requirements Add payment retry logic     # 1. Analyze and decompose
/architect                                # 2. Design (for tasks > 50 lines)
/task plan                                # 3. Create .agent/tasks/*.md files
/task next                                # 4. Get the first task
/implement TASK-001: ...                  # 5. Implement one task at a time
/task done TASK-001                       # 6. Mark done, get next
/docs src/payments/retry.service.ts       # 7. Document new code
/security-audit diff                      # 8. Security check (ALWAYS before PR)
/qa                                       # 9. Quality gates
/review                                   # 10. Final code review

# Commit and open PR
git commit -m "feat(payments): add retry logic"
gh pr create --fill
```

**Full workflow guide:** [`docs/guides/ai-workflow.md`](ai-workflow.md)

---

## Setting Up the Autonomous Agent (Optional)

Skip this section if you are not using autonomous JIRA-driven development.

### 1. Configure the issue tracker

Edit `agent.config.yaml`:
```yaml
agent:
  mode: semi-autonomous         # Start here; move to autonomous after testing
issue_tracker:
  provider: jira                # or: linear, github, azure-devops
  jira:
    server_url: "${JIRA_URL}"
    project_key: "YOUR_KEY"
```

For self-hosted Jira (Data Center): see [`.initium/docs/agent/jira-server-setup.md`](../../.initium/docs/agent/jira-server-setup.md).

### 2. Define the project domain

Fill in `docs/context/domain-boundaries.md` — controls which JIRA issues the agent accepts:
```
✅ In scope:  "Add retry logic to payment webhook handler"
❌ Out of scope: "Update marketing landing page" → Marketing team
```

### 3. Add agent environment variables to `.env`

```env
JIRA_URL=https://jira.yourcompany.com
JIRA_EMAIL=your-username
JIRA_API_TOKEN=your-pat-token
SLACK_WEBHOOK_URL=https://hooks.slack.com/...
```

### 4. Test the setup

```bash
# Verify Jira API access
curl -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/2/myself" | jq .displayName

# Triage a known issue manually
/triage YOUR-PROJECT-1

# Run the full loop on a test issue
/loop YOUR-PROJECT-1
```

Full documentation: [`.initium/docs/agent/autonomous-workflow.md`](../../.initium/docs/agent/autonomous-workflow.md).
`/loop` spawns specialist subagents per phase when the harness allows — see
[subagents.md](../../.initium/docs/agent/subagents.md).

---

## Security Checklist (Before Every PR)

Run `/security-audit diff` before opening any PR:

- [ ] No CRITICAL or HIGH findings
- [ ] No committed secrets, API keys, or credentials
- [ ] All user inputs validated at the entry point
- [ ] Authorization checked before data access
- [ ] No dependency CVEs with CVSS ≥ 7.0

See [`docs/guides/workflows/05-security-evaluation.md`](workflows/05-security-evaluation.md) for the full security workflow.

Guardrail hooks enforce the basics automatically: agents cannot read `.env` or key files, run
destructive or force-push commands, or edit protected paths without asking, and the pre-commit
hook rejects secret files and tokens. `setup.sh` enables the pre-commit hook; if you skipped it,
run `git config core.hooksPath .githooks`. See [guardrails.md](../../.initium/docs/guardrails.md).

---

## Keeping Your Setup Up to Date

When the team updates Initium (new commands, improved skill rules, security fixes):

```bash
# macOS / Linux
bash .initium/scripts/sync.sh --check    # check if update available
bash .initium/scripts/sync.sh            # apply updates interactively
```

```powershell
# Windows
.\.initium\scripts\sync.ps1 -Check
.\.initium\scripts\sync.ps1
```

The sync script never touches your project-specific files (`AGENTS.md`, `docs/context/`, `agent.config.yaml`). Inside an AI tool, `/sync-initium` does the same with a guided merge. See [`.initium/docs/sync-guide.md`](../../.initium/docs/sync-guide.md) for details.

---

## Key Commands

```bash
# TODO: Replace these with actual project commands

# Development
bun dev           # Start dev server

# Testing
bun test          # Run all tests
bun test --watch  # Watch mode

# Code quality
bun lint          # Lint
bun typecheck     # Type check
bun format        # Format

# Database
bun db:migrate    # Run migrations
bun db:seed       # Seed data

# Build
bun build         # Production build
```

---

## Getting Help

**Not sure what to do next? Ask the AI.**

In Claude Code, type `/help` and describe your situation in plain language:

```
/help                              # show all commands and the full workflow
/help how do I start a new feature?
/help how do I write tests for this module?
/help I'm getting a type error in the service layer
/help what should I do before opening a PR?
```

In Cursor, type `/help` in the chat followed by your question — slash commands from `.claude/commands/` work in Cursor directly.

The `/help` command will identify where you are in the workflow, map your question to the right command(s), and give you a clear next step — without writing any code.

| Need | Resource |
|------|---------|
| Don't know what to do | `/help` in Claude Code or Cursor |
| Project questions | `#<channel>` on Slack / Teams |
| AI workflow guidance | [`docs/guides/ai-workflow.md`](ai-workflow.md) |
| Autonomous agent issues | [`.initium/docs/agent/escalation-protocol.md`](../../.initium/docs/agent/escalation-protocol.md) |
| Initium bug or improvement | Open an issue in the Initium repository |

---

## First Task Checklist

Once setup is complete:

1. Pick up a `good-first-issue` ticket from the backlog
2. `/requirements <issue description>` — analyze and decompose
3. `/architect <issue description>` — design the implementation
4. `/task plan` — create task files from the design output
5. Implement task by task: `/task next` → `/implement TASK-XXX` → `/task done TASK-XXX`
6. `/security-audit diff` — fix any CRITICAL/HIGH findings
7. `/qa` — fix any blocking quality issues
8. `/review` — address any feedback
9. Open a PR using the template

Good luck, and don't hesitate to ask for help!
