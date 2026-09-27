<p align="center">
  <img src="assets/logo-header.svg" alt="Initium — AI-Native Development Skeleton" width="1200"/>
</p>

A production-ready starter for **AI-Native agentic development** — from interactive human-guided coding all the way to a fully autonomous agent that pulls work from JIRA, validates domain relevance, and delivers Pull Requests without manual intervention.

Supports [Cursor](https://cursor.sh), [Continue](https://continue.dev), [Claude Code](https://claude.ai/code), and [OpenCode](https://opencode.ai) out of the box.

> **Turkish / Türkçe:** [README.tr.md](README.tr.md) · **AI Workflow:** [docs/guides/ai-workflow.md](docs/guides/ai-workflow.md)

---

## What This Provides

| Layer | Config | Purpose |
|-------|--------|---------|
| **All agents** | `AGENTS.md` | Single source of project instructions (Claude Code loads it via `@AGENTS.md` in `CLAUDE.md`) |
| **Agent Skills** | `.claude/skills/<name>/SKILL.md` | 37 skills (stacks + UI design) in the open Agent Skills format — loaded on demand by Claude Code, Cursor, and OpenCode |
| **Claude Code** | `CLAUDE.md`, `.claude/` | 40 slash commands, event hooks |
| **Cursor** | `.cursor/rules/`, `.claude/skills/`, `.claude/commands/` | 6 base rules + shared skills and slash commands |
| **OpenCode** | `opencode.json`, `.opencode/commands/` | Reads `AGENTS.md` and skills natively; slash commands synced from `.claude/commands/` |
| **Continue** | `.continue/` | Multi-model setup, 37 skill rules generated from `.claude/skills/`, persistent guidelines |
| **Autonomous Agent** | `agent.config.yaml`, `.initium/docs/agent/` | JIRA polling, domain triage, full dev loop, escalation system |
| **Code graph** | `agent.config.yaml → codegraph`, `/codegraph` | Optional structural code index (MCP) so agents query symbols and callers instead of reading whole files |
| **GitHub** | `.github/` | PR template, issue templates, CI workflow template |
| **Initium sync** | `.initium/initium.json`, `.initium/scripts/sync.{sh,ps1,cmd}` | Pull improvements from upstream Initium without overwriting customizations |

---

## Quick Start

```bash
# 1. Clone
git clone <this-repo> my-project && cd my-project

# 2. Initialize (git, .env, checks)
./.initium/scripts/setup.sh          # macOS/Linux
# .initium\scripts\setup.cmd         # Windows (Batch)
# .\.initium\scripts\setup.ps1       # Windows (PowerShell)

# 3. Run interactive wizard — fills project name, stack, tracker keys
bash .initium/scripts/init.sh

# 4. Let AI populate all remaining TODO files
claude
/init I'm building a <type> called <name> for <users>. Stack: <language, framework, DB>.

# 5. Verify
bash .initium/scripts/validate.sh   # expect: all PASS, no FAIL
```

After setup, code with the AI loop:
```
/requirements <your first feature>   →  /architect  →  /task plan  →  /implement  →  /qa  →  /deploy
```

> **New to the project or unsure what to do?** Type `/help` in Claude Code or Cursor — the AI will guide you to the right command for your situation.

---

## Customization Checklist

### Automated by `.initium/scripts/init.sh` + `/init`

| File | How it's populated |
|------|--------------------|
| `AGENTS.md` | Wizard fills mechanical fields; AI fills conventions |
| `.cursor/rules/00-project-overview.mdc` | Same as AGENTS.md |
| `docs/context/project-brief.md` | AI-generated from your description |
| `docs/context/tech-stack.md` | AI-generated from confirmed stack |
| `docs/context/domain-boundaries.md` | AI-generated — **critical for autonomous agent** |
| `docs/context/domain-glossary.md` | AI-generated from domain analysis |
| `docs/architecture/overview.md` | AI-generated architecture template |
| `agent.config.yaml` | Wizard fills IDs; `/init agent:` fills tracker keys |
| `.github/workflows/ci.yml` | `/init ci:` generates per detected stack |

### Requires manual action
- [ ] `.continue/config.yaml` — add API key(s); uncomment your stack's skill rules
- [ ] `.env` — fill in credentials (copy from `.env.example`)
- [ ] `.cursor/mcp.json` — enable MCP servers by removing `"disabled": true`
- [ ] Review and refine all AI-generated content before first commit

---

## Repository Structure

```
.
├── AGENTS.md                           # ← CUSTOMIZE — project instructions for every AI agent
├── CLAUDE.md                           # Imports AGENTS.md for Claude Code — do not add content
├── agent.config.yaml                   # ← CUSTOMIZE — autonomous agent configuration
├── .initium/
│   ├── initium.json                   # Tracks which Initium version this project is based on
│   ├── scripts/                       # Initium lifecycle scripts (setup, sync, validate)
│   └── docs/                          # Initium documentation (sync guide, update notes)
│
├── .claude/
│   ├── settings.json                   # Tool permissions + event hooks
│   ├── skills/                         # 37 Agent Skills — <name>/SKILL.md (single source)
│   │   ├── lang-*/                     # Java, .NET, Python, TypeScript, Go, Rust, Kotlin, PHP
│   │   ├── be-*/                       # Microservices, Node.js, messaging, GraphQL/gRPC
│   │   ├── fe-*/  mobile-*/            # React, Next.js, Vue, Angular · iOS, Android, KMP, Flutter, RN
│   │   ├── devops-*/                   # Docker, CI/CD, Terraform, observability, AWS, GCP, on-prem
│   │   ├── design-*/                   # Apple HIG, Material 3, design tokens / DESIGN.md
│   │   ├── frontend-design/ impeccable/ # Vendored web design skills (Apache-2.0, see THIRD_PARTY_NOTICES.md)
│   │   └── ai-llm-apps/ db-migrations/ docs-generation/ security-sast/
│   ├── agents/                         # Subagents used by the impeccable skill
│   ├── commands/                       # 40 slash commands (type / in Claude Code)
│   │   ├── help.md                     # /help — guide to commands and workflows
│   │   ├── goal.md                     # /goal — pursue one objective until done
│   │   ├── init.md                     # /init — project setup wizard
│   │   ├── requirements.md             # /requirements
│   │   ├── architect.md                # /architect
│   │   ├── implement.md                # /implement
│   │   ├── task.md                     # /task — task planning + tracking
│   │   ├── review.md                   # /review
│   │   ├── qa.md                       # /qa
│   │   ├── security-audit.md           # /security-audit
│   │   ├── test.md                     # /test
│   │   ├── debug.md                    # /debug
│   │   ├── deploy.md                   # /deploy
│   │   ├── infra.md                    # /infra
│   │   ├── migrate.md                  # /migrate
│   │   ├── db.md                       # /db
│   │   ├── sprint.md                   # /sprint
│   │   ├── docs.md                     # /docs
│   │   ├── doc-api.md                  # /doc-api — OpenAPI spec generation
│   │   ├── doc-diagrams.md             # /doc-diagrams — sequence diagrams for API & business flows
│   │   ├── doc-site.md                 # /doc-site — documentation website
│   │   ├── doc-changelog.md            # /doc-changelog — CHANGELOG from git history
│   │   ├── doc-schema.md               # /doc-schema — database ERD + table reference
│   │   ├── standup.md                  # /standup
│   │   ├── sync-initium.md             # /sync-initium — apply upstream Initium updates
│   │   ├── codegraph.md                # /codegraph — code graph setup, queries, impact
│   │   ├── refactor.md                 # /refactor
│   │   ├── upgrade.md                  # /upgrade — dependency / framework upgrades
│   │   ├── perf.md                     # /perf
│   │   ├── a11y.md                     # /a11y — WCAG 2.2 AA audit
│   │   ├── design.md                   # /design — build UI that doesn't look templated
│   │   ├── design-review.md            # /design-review — template tells + HIG / Material 3 review
│   │   ├── polish.md                   # /polish — final visual quality pass
│   │   ├── design-system.md            # /design-system — DESIGN.md, PRODUCT.md, tokens
│   │   ├── eval.md                     # /eval — LLM feature evaluations
│   │   ├── skill.md                    # /skill — create or update Agent Skills
│   │   ├── triage.md                   # /triage        ← autonomous agent
│   │   ├── groom.md                    # /groom         ← autonomous agent
│   │   ├── loop.md                     # /loop          ← autonomous agent
│   │   └── escalate.md                 # /escalate      ← autonomous agent
│   └── hooks/
│       ├── post-write.mjs              # Guards protected paths on every file write
│       ├── audit-log.mjs               # Records every bash command + exit code
│       └── on-stop.mjs                 # Session-end: warns about in-flight agent tasks
│
├── .cursor/
│   ├── prompts/                        # Cursor prompt files — mirror of Claude commands
│   ├── rules/
│   │   ├── 00-project-overview.mdc    # ← CUSTOMIZE — always loaded by Cursor
│   │   ├── 01-coding-standards.mdc
│   │   ├── 02-architecture.mdc
│   │   ├── 03-testing.mdc
│   │   ├── 04-git-workflow.mdc
│   │   └── 05-security.mdc            # OWASP Top 10 — always loaded
│   └── mcp.json                       # MCP servers: GitHub, Jira, Linear, Slack, Sentry…
│
├── .continue/
│   ├── config.yaml                    # ← ADD API KEYS + uncomment your skills
│   └── rules/
│       ├── 01-coding-standards.md … 04-security.md
│       └── skills/                    # 37 files — generated from .claude/skills/ (sync-skills.mjs)
│
├── .opencode/
│   └── commands/                      # 40 slash commands (mirrors .claude/commands/)
├── opencode.json                      # OpenCode instructions (.cursor/rules) + code graph MCP
│
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
│       ├── ci.yml                     # CI template — adapt for your stack
│       └── initium-sync.yml           # Weekly Initium update check → PR
│
├── docs/
│   ├── guides/                        # Initium-provided guidance — customize freely
│   │   ├── ai-workflow.md             # AI-Native development workflow (English)
│   │   ├── ai-workflow.tr.md          # AI-Native development workflow (Turkish)
│   │   ├── onboarding.md              # New developer onboarding guide
│   │   ├── team.md                    # Team roles and AI-native optimization
│   │   ├── agent/                     # Autonomous agent documentation
│   │   │   ├── autonomous-workflow.md    # State machine, phases, gates, resume
│   │   │   ├── escalation-protocol.md    # Triggers, severity levels, human responses
│   │   │   ├── security-evaluator.md     # Security integration in the agent loop
│   │   │   ├── documentation-agent.md    # Documentation generation architecture
│   │   │   ├── jira-server-setup.md      # On-premise Jira Server operator guide
│   │   │   ├── decision-log-template.md  # Audit trail schema
│   │   │   └── schemas/                  # JSON schemas: task-state, qa-report, security-report…
│   │   └── workflows/                 # Detailed workflow guides (7 files)
│   │       ├── 01 … 04               # Requirements, feature dev, testing, deployment
│   │       ├── 05-security-evaluation.md
│   │       ├── 06-database-migrations.md
│   │       └── 07-deployment-platforms.md
│   ├── context/                       # ← CUSTOMIZE — AI context for tools and agent
│   │   ├── project-brief.md
│   │   ├── tech-stack.md
│   │   ├── domain-glossary.md
│   │   └── domain-boundaries.md      # ← CRITICAL for autonomous agent triage
│   └── architecture/
│       ├── overview.md               # ← CUSTOMIZE — system architecture
│       └── decisions/                # Architecture Decision Records (ADR)
│
├── skills/
│   └── README.md                     # Skills index, activation guide, how to add new skills
│
├── .agent/
│   ├── tasks/                        # ← Per-feature task files created by /task plan
│   │   ├── TASK-001-*.md             #   One file per task: status, AC, dependencies
│   │   └── INDEX.md                  #   Execution order and progress summary
│   ├── outputs/                      # Agent pipeline artifacts (requirements, design, QA JSONs)
│   └── audit/                        # JSONL audit trail of all agent actions
│
├── .agent-templates/
│   └── webhook-receiver.mjs          # Jira Server webhook receiver (copy to .agent/)
│
└── .initium/
    ├── initium.json                 # Tracks which Initium version this project is based on
    ├── scripts/
    │   ├── setup.{sh,cmd,ps1}       # Step 1 — initialize project
    │   ├── init.{sh,cmd,ps1}        # Step 2 — interactive configuration wizard
    │   ├── validate.{sh,cmd,ps1}    # 128-point configuration validator
    │   └── sync.{sh,ps1,cmd}        # Pull upstream Initium improvements

    │   ├── Dockerfile               # Image: Node 22 + Claude Code CLI + git + cron
    │   ├── docker-compose.yml       # Service definition with all env vars
    │   ├── entrypoint.sh            # Startup: clone repo, overlay tooling, start cron
    │   ├── groom-runner.sh          # Cron payload: git pull → /groom → git push
    │   ├── webhook-entrypoint.sh    # Webhook mode (falls back to cron if secret unset)
    │   └── .env.example             # All supported variables documented
    └── docs/
        ├── sync-guide.md            # Sync guide and merge strategies
        ├── UPDATES.md               # Migration notes for each Initium version
        └── agent/                   # Autonomous agent documentation
            ├── autonomous-workflow.md   # State machine, phases, gates
            ├── docker-agent.md          # Containerized agent setup guide
            ├── escalation-protocol.md   # Triggers, severity levels, human responses
            ├── jira-server-setup.md     # On-premise Jira Server operator guide
            ├── security-evaluator.md    # Security integration in the agent loop
            ├── documentation-agent.md   # Documentation generation architecture
            └── decision-log-template.md # Audit trail schema
```

---

## Slash Commands Reference

### Help & Navigation

| Command | Purpose |
|---------|---------|
| `/help` | Show all available commands and the typical workflow |
| `/help <question>` | Get directed to the right command for your specific situation |
| `/help <phase>` | "how do I start a feature?" — prints the step-by-step command sequence for that phase |

> **Tip for newcomers:** `/help` is always your first command when you're unsure what to do next. Describe your situation in plain language and the AI will point you to the right workflow and commands.

### Initialization

| Command | Purpose |
|---------|---------|
| `/init <description>` | Populate all TODO files from a free-form project description |
| `/init domain: <desc>` | Generate domain boundaries, glossary, and agent scope keywords |
| `/init stack: <stack>` | Generate tech stack doc and AGENTS.md commands section |
| `/init ci: <stack>` | Generate real CI workflow steps for your language and deploy target |
| `/init agent: <keys>` | Configure tracker keys, GitHub owner/repo, escalation channels |

### Human-Guided Development

| Command | Purpose | When |
|---------|---------|------|
| `/requirements` | → user stories + acceptance criteria + ordered task backlog + DoD | Before any feature |
| `/architect` | Design before a single line of code | Tasks > 50 lines |
| `/task plan` | Break design output into tracked `.agent/tasks/*.md` files | After architect, before coding |
| `/task next` | Get the next actionable task respecting dependencies | During implementation |
| `/task done <id>` | Mark a task complete and unblock dependents | After each commit |
| `/task list` | Show all tasks and their status | Anytime |
| `/task status` | Progress dashboard with percentage and critical path | Anytime |
| `/implement` | Bottom-up implementation with self-review | During coding |
| `/goal <objective>` | Pursue one primary goal until Definition of Done — no stopping mid-way | End-to-end delivery |
| `/qa` | Lint + types + tests + coverage + security | Before opening PR |
| `/security-audit [target]` | OWASP Top 10 + CVE + secret scan | Before every PR |
| `/review` | Code review against standards and OWASP | After implementation |
| `/test` | Generate comprehensive tests (happy path + edges + errors) | Any module |
| `/debug` | Systematic diagnosis: hypotheses → fix → prevention | When stuck |
| `/deploy` | Pre-deploy checklist + execution steps + monitoring plan | Before every deploy |
| `/infra <platform>` | Scaffold Terraform / K8s / CI for AWS, GCP, or on-prem | New deployment target |
| `/migrate` | Safe DB migration: Expand-Contract + batch + rollback | Schema changes |
| `/db <subcommand>` | Database lifecycle: `init`, `create`, `dml`, `seed`, `status`, `diff` | DB management |
| `/sprint` | Sprint planning: capacity + backlog + tasks + risk register | Sprint kickoff |
| `/standup` | Daily summary from git history | Start of day |
| `/docs <file>` | Generate code-level documentation (JSDoc, docstrings, GoDoc…) | After implementation |
| `/refactor` | Behavior-preserving refactor with characterization tests | Tech debt, before extending messy code |
| `/upgrade [audit\|<pkg>\|security\|runtime]` | Audit or upgrade dependencies, frameworks, runtimes with migration guides | Outdated deps, CVEs |
| `/perf` | Baseline → profile → fix → re-measure, with a regression guard | Latency, memory, bundle size |
| `/a11y [scope]` | WCAG 2.2 AA audit (automated + manual) and fixes for web and mobile | UI changes |
| `/eval [create\|run\|compare]` | Evaluation suites for LLM features: datasets, graders, thresholds, CI | Prompt / model / RAG changes |

### UI & Visual Design

| Command | Purpose | When to use |
|---------|---------|-------------|
| `/design <target + brief>` | Context → written direction (tokens, wireframe, one signature element) → build → screenshot critique | New page, screen, or component |
| `/design-review [scope]` | Read-only review: generic "AI template" tells, craft, states, Apple HIG / Material 3 fit, scored report | Before merging UI, "this looks generic" |
| `/polish [scope]` | Final pass: broken layout, missing states, token consistency, typography, template tells | Before shipping |
| `/design-system [scan\|seed\|check\|tokens]` | Create or refresh `DESIGN.md` (Google DESIGN.md format) and `PRODUCT.md`; generate token files | Once per project, after visual changes |

Web surfaces use the vendored [`frontend-design`](https://github.com/anthropics/skills/tree/main/skills/frontend-design) (Anthropic) and [`impeccable`](https://github.com/pbakaus/impeccable) (Paul Bakaus) skills; native apps use `design-apple-hig` (a summary that links to Apple's guidelines) and `design-material3`. `impeccable` also works on its own: `/impeccable critique`, `/impeccable polish`, and more. For its detector, design hook, and live browser mode, run `npx impeccable install`. For Apple docs as Markdown, enable the `sosumi` MCP server in `.cursor/mcp.json` / `opencode.json`.

### Context & Knowledge

| Command | Purpose |
|---------|---------|
| `/codegraph [setup\|status\|query\|impact\|refresh]` | Structural code graph via MCP (`codebase-memory-mcp` by default): symbol search, call traces, diff impact — fewer tokens than grep + read |
| `/skill [new\|update\|list]` | Create or update Agent Skills in `.claude/skills/` from the codebase's real conventions |

### Documentation Generation

| Command | Purpose | Output |
|---------|---------|--------|
| `/doc-api` | Generate OpenAPI 3.x spec + validate + ReDoc HTML | `openapi.json` + `docs/api/` |
| `/doc-diagrams` | Generate Mermaid sequence diagrams for API calls and business flows | `docs/diagrams/` |
| `/doc-site` | Scaffold or rebuild docs website (Docusaurus / MkDocs) | Deployable static site |
| `/doc-changelog` | Generate `CHANGELOG.md` from git history (git-cliff) | `CHANGELOG.md` + stakeholder summary |
| `/doc-schema` | Database ERD + table reference + index analysis | `docs/database/` |

### Autonomous Agent

| Command | Purpose |
|---------|---------|
| `/triage <issue>` | Domain relevance check: auto-accept ≥ 0.80, escalate 0.30–0.79, reject < 0.30 |
| `/groom` | Batch-process backlog: triage + requirements for each accepted issue |
| `/loop <task-id>` | Full autonomous loop: design → implement → docs → QA → security → PR → deploy |
| `/escalate <sev> <trigger> <id>` | Structured human notification with Slack/GitHub/email routing |

### Initium Maintenance

| Command | Purpose |
|---------|---------|
| `/sync-initium` | Pull improvements from upstream Initium into this project |
| `/sync-initium --dry-run` | Preview what would change without applying anything |
| `/sync-initium --check` | Check if an Initium update is available |
| `/sync-initium --ref <tag>` | Sync to a specific Initium release |

---

## Autonomous Agent Loop

```
JIRA / Linear / GitHub Issues
    │
    ▼ /groom (scheduled or webhook)
    ▼ /triage — confidence scoring
    │   Entity match +0.30 · Functional area +0.40 · Code ownership +0.20
    │   ≥ 0.80 → ACCEPT   0.30–0.79 → ESCALATE   < 0.30 → REJECT
    ▼
    ▼ /requirements — user stories + task backlog (JSON + Markdown)
    ▼ /architect — design doc + risk level
    │   risk=HIGH → human approval gate (AGENT_APPROVE_DESIGN)
    ▼ /task plan — materialize tasks into .agent/tasks/*.md files
    │   each file: status, acceptance criteria, dependencies
    ▼
    ▼ /loop per task (reads .agent/tasks/ if present):
    │   /task next → implement → /docs → test → /task done → next task
    │   fail? → /debug (max retries) → escalate
    ▼ docs sync (conditional):
    │   apiChanges → /doc-api diff · schemaChanges → /doc-schema migrations
    ▼ /qa — lint + types + coverage + security
    ▼ /security-audit diff — OWASP + CVE check
    ▼ PR created (linked to issue, QA report, risk level)
    ▼ CI monitored → merge (auto or human)
    ▼ /deploy staging (auto) → production (human gate)
    ▼ 30-min post-deploy monitoring
    │   metric spike → auto-rollback + critical escalation
    ▼ Issue tracker: Done ✓ · Audit log written
```

**Safety:** persistent state (resume on crash) · kill switch (`touch .agent/STOP`) · protected paths · JSONL audit trail

**Human response commands** (post on GitHub issue or JIRA ticket):
`AGENT_RESUME` · `AGENT_APPROVE_DESIGN` · `AGENT_APPROVE_DEPLOY` · `AGENT_CLARIFY: <text>` · `AGENT_SKIP_TASK` · `AGENT_REASSIGN` · `AGENT_ABANDON`

---

## Containerized Agent (Docker)

Run the autonomous agent as a long-lived container — no developer machine required. The image contains the full Initium runtime; your project source is never bundled into the image and is cloned at startup.

Two trigger modes — use one or both:

```bash
# Polling only (cron-based /groom)
cp .initium/docker/.env.example .initium/docker/.env   # fill in keys
docker compose -f .initium/docker/docker-compose.yml up -d agent
docker logs -f initium-agent

# + Webhook receiver (Jira Server event-driven, instant triage)
# also set JIRA_WEBHOOK_SECRET in .initium/docker/.env, then:
docker compose -f .initium/docker/docker-compose.yml up -d
# point Jira Server → http://<host>:3001/jira-webhook
```

**Tooling overlay** — on first startup the container clones your repo into `/workspace/`. If the repo was not already initialized with Initium, the following directories are automatically overlaid from the baked image before the first cron run:

| Directory | Contents |
|-----------|----------|
| `.claude/` | Slash commands, hooks, settings |
| `.cursor/` | Rules, MCP config |
| `.continue/` | Multi-model config, skill rules |
| `agent.config.yaml` | Agent runtime config |

Directories already present in your repo are never overwritten — your customizations take precedence.

**Supported AI providers** — set one group of env vars:

| Provider | Required variables |
|----------|--------------------|
| Anthropic (direct) | `ANTHROPIC_API_KEY` |
| AWS Bedrock | `CLAUDE_CODE_USE_BEDROCK=1` · `AWS_ACCESS_KEY_ID` · `AWS_SECRET_ACCESS_KEY` · `AWS_REGION` |
| Google Vertex AI | `CLAUDE_CODE_USE_VERTEX=1` · `CLOUD_ML_REGION` · `ANTHROPIC_VERTEX_PROJECT_ID` |

**Schedule** — controlled by `GROOM_CRON` (standard cron syntax). Defaults to `*/15 * * * *` (every 15 minutes, matching `agent.config.yaml → poll_interval_minutes`).

**Kill switch** — create `.agent/STOP` in the workspace to halt the agent immediately without stopping the container.

See [.initium/docs/agent/docker-agent.md](.initium/docs/agent/docker-agent.md) for the full setup guide.

---

## Language & Framework Skills

Skills provide deep, idiomatic guidance in the open [Agent Skills](https://agentskills.io) format. Claude Code, Cursor, and OpenCode load them on demand from `.claude/skills/` (only the description costs context until a skill is used); Continue requires uncommenting the generated rule in `.continue/config.yaml`.

| Category | Skills |
|----------|--------|
| **Backend** | Java/Spring Boot · .NET/ASP.NET Core · Python/FastAPI · TypeScript · Node.js (NestJS/Fastify/Hono) · Go · Rust (Axum/Tokio) · Kotlin (Ktor/Spring) · PHP (Laravel) |
| **APIs & Integration** | Microservices · Messaging (Kafka/RabbitMQ/SQS, outbox) · GraphQL & gRPC |
| **AI / LLM** | LLM applications: structured output, RAG, OWASP LLM Top 10, evals, MCP servers |
| **Frontend** | React · Next.js App Router · Vue 3 · Angular 17+ |
| **Mobile** | iOS/Swift · Android/Kotlin · Kotlin Multiplatform · Flutter/Dart · React Native/Expo |
| **UI Design** | Web visual design (`frontend-design`, `impeccable`) · Apple Human Interface Guidelines · Material Design 3 Expressive · Design tokens & DESIGN.md |
| **Infrastructure** | Docker · GitHub Actions CI/CD · Terraform/OpenTofu · OpenTelemetry & SLOs · AWS · GCP · On-Premise (k3s/Vault/Ansible) |
| **Cross-cutting** | Database Migrations · Security SAST · Documentation Generation |

See [skills/README.md](skills/README.md) for the full index, activation guide, and how to add new skills.

---

## MCP Servers

Configured in `.cursor/mcp.json`. Enable a server: remove `"disabled": true` and set its env vars.

| Server | Purpose | Env vars |
|--------|---------|---------|
| `filesystem` · `git` | Workspace files, git history | — (auto) |
| `github` | Issues, PRs, CI status | `GITHUB_TOKEN` |
| `jira` | Pull/update issues — used by `/triage`, `/groom` | `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` |
| `linear` | Alternative to Jira | `LINEAR_API_KEY` |
| `slack` | Escalation notifications | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` |
| `sentry` | Post-deploy error monitoring | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG` |
| `postgres` · `brave-search` · `memory` · `puppeteer` | DB inspection, web search, memory, browser automation | see `.cursor/mcp.json` |

---

## Keeping Your Project Up to Date

Updates arrive automatically:

- **Weekly pull request.** `.github/workflows/initium-sync.yml` checks every Monday for a new Initium
  release and opens a `chore/initium-sync-v<version>` PR containing the Initium-owned file updates,
  a checklist of `merge_required` files to merge by hand, and the release notes. Nothing is merged
  automatically. One-time setup: enable *Settings → Actions → General → Allow GitHub Actions to
  create and approve pull requests*.
- **Session notice.** A Claude Code `SessionStart` hook (`check-update.mjs`, cached daily) tells the
  agent when a newer release exists, so it can suggest `/sync-initium`.
- **Settings.** `agent.config.yaml → initium_sync`: `channel` (`tags` = releases only, or `main`),
  `auto_pr`, `notify_local`, `check_interval_hours`.

To sync by hand:

```bash
# macOS / Linux / Git Bash
bash .initium/scripts/sync.sh              # interactive: shows diff, auto-applies safe files
bash .initium/scripts/sync.sh --auto       # non-interactive: apply Initium-owned files, skip merges
bash .initium/scripts/sync.sh --check      # exit 10 if an update is available (--json for scripts)
bash .initium/scripts/sync.sh --ref v1.2.0 # pin a specific release
```

```powershell
# Windows (PowerShell — recommended)
.\.initium\scripts\sync.ps1            # interactive
.\.initium\scripts\sync.ps1 -Auto     # non-interactive
.\.initium\scripts\sync.ps1 -Check    # check only
```

```bat
:: Windows (Batch — delegates to PowerShell automatically)
.initium\scripts\sync.cmd
.initium\scripts\sync.cmd --auto
.initium\scripts\sync.cmd --check
```

The sync script uses `.initium/initium.json` to classify every file:
- **Initium-owned** (commands, skill rules, agent docs) → auto-applied safely; files Initium deleted are removed if you never changed them
- **merge-required** (`.continue/config.yaml`, `mcp.json`, `ci.yml`) → shown as diff, you decide
- **project-owned** (`AGENTS.md`, `CLAUDE.md`, `docs/context/`, `agent.config.yaml`) → never touched

See [.initium/docs/sync-guide.md](.initium/docs/sync-guide.md) for the full guide, including merge strategies for each file type and how to maintain an organizational fork.

---

## Core Principles

1. **Context is everything.** AI produces better output when it understands your project's purpose and constraints. The `docs/context/` files and skill rules exist to provide this context persistently — no need to repeat it in every prompt.

2. **Rules over repetition.** Define standards once in skill files. "Use constructor injection", "always write tests", "parameterize all queries" — say it once, every session enforces it.

3. **Structured workflows.** Slash commands encode recurring workflows so AI executes them consistently — from a raw requirement to a merged, deployed, documented PR.

4. **Humans set limits, agents execute.** The agent acts autonomously within configured thresholds. Every risky decision (high-risk design, production deploy) requires human approval. Every action is logged.

---

## Further Reading

| Document | Contents |
|----------|---------|
| [docs/guides/ai-workflow.md](docs/guides/ai-workflow.md) | Full AI-Native development workflow reference |
| [docs/guides/team.md](docs/guides/team.md) | Team roles, structure, and optimization for AI-native development |
| [docs/guides/team.tr.md](docs/guides/team.tr.md) | Ekip rolleri ve optimizasyon kılavuzu (Türkçe) |
| [docs/guides/onboarding.md](docs/guides/onboarding.md) | New developer setup guide |
| [docs/guides/onboarding.tr.md](docs/guides/onboarding.tr.md) | Yeni geliştirici kurulum kılavuzu (Türkçe) |
| [.initium/docs/sync-guide.md](.initium/docs/sync-guide.md) | How to apply Initium updates to your project |
| [.initium/docs/agent/autonomous-workflow.md](.initium/docs/agent/autonomous-workflow.md) | Agent state machine, phases, gates |
| [.initium/docs/agent/docker-agent.md](.initium/docs/agent/docker-agent.md) | Containerized agent setup, env vars, troubleshooting |
| [.initium/docs/agent/jira-server-setup.md](.initium/docs/agent/jira-server-setup.md) | On-premise Jira Server operator guide |
| [.initium/docs/agent/security-evaluator.md](.initium/docs/agent/security-evaluator.md) | Security evaluation architecture |
| [.initium/docs/agent/documentation-agent.md](.initium/docs/agent/documentation-agent.md) | Documentation generation tools and pipeline |
| [skills/README.md](skills/README.md) | Complete skills index and activation guide |
| [.initium/docs/UPDATES.md](.initium/docs/UPDATES.md) | Changelog for Initium versions |
