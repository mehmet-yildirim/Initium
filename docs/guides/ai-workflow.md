# AI-Native Development Workflow

This document describes how to work effectively with AI tools in this project.
Following this workflow produces faster, higher-quality results.

> **Türkçe:** [docs/guides/ai-workflow.tr.md](ai-workflow.tr.md) — Türkçe sürüm için bakın.
>
> **Not sure which command to use?** Run `/help <your question>` — it maps your situation to the
> right command sequence without touching any code.

---

## The AI-Native Loop

```
1. CONTEXT   → Give AI the right information before asking for code
2. SPECIFY   → Turn the idea into stories and acceptance criteria  (/requirements)
3. DESIGN    → Have AI design before it codes                       (/architect)
4. PLAN      → Break the design into tracked tasks                  (/task plan)
5. IMPLEMENT → Implement with AI one task at a time                 (/task next → /implement)
6. SECURITY  → Evaluate every change for risks                      (/security-audit)
7. VERIFY    → Quality gates and critical review                    (/qa → /review)
8. DOCUMENT  → Update docs while context is fresh                   (/docs)
```

### Autonomous Mode (agent drives the loop)

```
Backlog ──▶ /groom ──▶ /triage (per issue) ──▶ /requirements ──▶ /loop ──▶ PR ──▶ /deploy
               │              │                                      │
         batch intake   domain check                        full loop per task:
                        accept / escalate / reject          architect → implement →
                                                            security-audit → qa → PR
```

---

## Tool Overview

| Tool | Best for | Key config |
|------|----------|-----------|
| **Claude Code** | Complex agentic tasks, multi-file edits, CLI | `AGENTS.md` (via `CLAUDE.md`), `.claude/commands/`, `.claude/skills/` |
| **Cursor** | In-editor generation, chat, autocomplete | `.cursor/rules/*.mdc`, `.cursor/mcp.json`; reads `.claude/commands/` and `.claude/skills/` |
| **OpenCode** | Terminal agent with any model provider | `AGENTS.md`, `opencode.json`, `.opencode/commands/` (mirror of `.claude/commands/`) |
| **Continue** | Inline edits, chat, autocomplete in VS Code / JetBrains | `.continue/config.yaml`, `.continue/rules/` |

All tools share the same slash command names. Edit commands only in `.claude/commands/`, then run
`bash .initium/scripts/sync-opencode-commands.sh` to refresh the OpenCode mirror.

---

## Human-Guided Workflow

### Step 1: Provide Context First

AI tools work best when they understand your project. Context is provided via:

- **`AGENTS.md`** — Project overview, commands, conventions (read natively by Cursor, OpenCode, Codex, Copilot; Claude Code loads it through the `@AGENTS.md` import in `CLAUDE.md`)
- **`.cursor/rules/`** — Persistent rules loaded for every Cursor interaction (auto by file type)
- **`.claude/skills/`** — 48 stack skills (languages, frameworks, mobile, DevOps, security, testing, design). Loaded on demand when the task or open files match a skill's description or `paths` — see [`skills/README.md`](../../skills/README.md)
- **`.continue/rules/`** — Rules included in Continue requests
- **`docs/context/`** — Deeper project context you can reference with `@docs`

On large codebases, set up the code graph once (`/codegraph setup`) so agents look up symbols,
callers, and impact instead of reading whole files.

**Before starting any significant task**, verify the AI has context:
> "What do you know about this project's architecture and coding standards?"

---

### Step 2: Analyze Requirements

For any non-trivial feature, run `/requirements` first:

```
/requirements Add a password reset flow with email verification
```

This produces: user stories, acceptance criteria, an ordered task backlog, and a Definition of Done.
Review before proceeding — AI may miss implied requirements or out-of-scope items.

---

### Step 3: Design Before Coding

For any feature > 50 lines, run `/architect`:

```
/architect Add a password reset flow with email verification
```

Review the design output critically:
- Does the approach fit our architecture and layer boundaries?
- Are all edge cases identified?
- Is the risk level acceptable? (`high` → get a second opinion)

Only proceed after approving the design.

---

### Step 4: Break the Design into Tasks

```
/task plan
```

Creates one Markdown file per task in `.agent/tasks/` (ID, estimate, dependencies, acceptance
criteria, files to change) — roughly one task per PR. Useful follow-ups:

```
/task list          # all tasks and their status
/task status        # progress dashboard
```

---

### Step 5: Implement One Task at a Time

```
/task next                                               # the next unblocked task
/implement TASK-001: Create PasswordReset entity and repository interface
/task done TASK-001                                      # unblocks dependent tasks
```

After each task:
- **Read and understand the generated code** — never accept code you don't understand
- Run the linter and type checker
- Run the tests for the changed module

When you want the agent to keep going until the whole Definition of Done is met — without
stopping between tasks — use `/goal <objective>` instead. For a hands-free run over the task list
with PR creation and CI monitoring, use `/loop` (see [Autonomous Agent Workflow](#autonomous-agent-workflow)).

---

### Step 6: Security Evaluation

Run `/security-audit` on every change that touches auth, user input, payments, or data access:

```
/security-audit diff          # scan only changes in this branch
/security-audit src/payments/ # scan a specific directory
```

**Never open a PR with a CRITICAL security finding.**

For scheduled or full scans:
```
/security-audit full          # entire codebase (deps + SAST + secrets)
/security-audit deps          # dependency CVE scan only
/security-audit secrets       # secret / credential scan only
```

**Action by severity:**

| Severity | Meaning | Action |
|----------|---------|--------|
| **CRITICAL** | Exploitable with direct business impact | Block the PR, fix immediately |
| **HIGH** | Significant, likely exploitable | Fix this sprint |
| **MEDIUM** | Requires specific conditions | Fix within 2 sprints |
| **LOW** | Defense-in-depth improvement | Fix when convenient |

---

### Step 7: Quality Assurance and Review

```
/qa
/review
```

`/qa` runs lint → type check → tests → coverage → dependency CVEs → self-review. Fix all blocking
issues before opening a PR. `/review` checks the diff against project standards, architecture
rules, and OWASP patterns. Address every raised issue or explicitly mark it "won't fix" with a reason.

---

### Step 8: Generate Missing Tests

If tests weren't generated during implementation:

```
/test src/auth/password-reset.service.ts
```

Verify the generated tests:
- Cover happy path, edge cases, and error cases
- Are not testing implementation details
- Actually fail when you introduce a bug

---

### Step 9: Document

After completing a feature:

```
/docs src/auth/password-reset.service.ts
```

Also update:
- `AGENTS.md` if new conventions or patterns were introduced
- `docs/architecture/decisions/` if a significant design decision was made
- `docs/context/domain-glossary.md` if new domain terms were introduced
- API contracts with `/doc-api`, schema docs with `/doc-schema`, flows with `/doc-diagrams`

---

## Specialized Workflows

| Situation | Command sequence |
|-----------|-----------------|
| Fixing a bug | `/debug <symptom>` → `/implement <fix>` → `/test` → `/qa` |
| Refactoring / tech debt | `/refactor <target>` (behavior-preserving, test safety net) → `/qa` → `/review` |
| Upgrading dependencies or runtimes | `/upgrade audit` → `/upgrade <package>` or `/upgrade security` or `/upgrade runtime <name> <version>` → `/qa` |
| Performance problem | `/perf <symptom or target>` — measure first, fix the bottleneck, measure again |
| New UI surface | `/design-system` (once per product) → `/design <screen>` → `/design-review` → `/polish` → `/a11y` |
| Accessibility audit | `/a11y <page, component, or diff>` (WCAG 2.2 AA) |
| LLM-powered feature | `/architect` → `/implement` → `/eval create <feature>` → `/eval run` after every prompt/model change → `/qa` |
| Database schema change | `/migrate <description>` (Expand-Contract + rollback); `/db status`, `/db diff`, `/db audit` for lifecycle checks |
| Infrastructure | `/infra <aws\|gcp\|azure\|onprem> init`, then `/infra <platform> ci\|secrets\|database\|monitoring` |
| Release | `/qa` → `/deploy <env>` → `/doc-changelog` |
| Documentation set | `/docs`, `/doc-api`, `/doc-schema`, `/doc-diagrams`, `/doc-site`, `/doc-changelog` |
| Teaching the AI a convention | `/skill new <topic>` or `/skill update <name>` |

---

## Autonomous Agent Workflow

The agent drives the full loop without manual intervention for each step.
See [`.initium/docs/agent/autonomous-workflow.md`](../../.initium/docs/agent/autonomous-workflow.md) for the full state machine.

### Starting the agent

```bash
# Process the backlog (triage + requirements analysis for accepted issues)
/groom

# Execute a specific accepted task end-to-end
/loop PROJ-42

# Resume a task that was interrupted
/loop resume PROJ-42
```

Create `.agent/STOP` to halt the agent at the next safety check.

### What the agent does automatically

```
/groom          → polls the tracker → /triage per issue → /requirements on accepted ones
/triage         → domain relevance scoring → ACCEPT / ESCALATE / REJECT
/loop           → /architect → create branch → /implement (retry loop) →
                  /security-audit → /qa → create PR → monitor CI →
                  /deploy staging → monitor post-deploy
/escalate       → notifies Slack / GitHub / tracker when the agent cannot proceed
```

### When the agent stops and waits for you

The agent escalates (pauses + notifies) when:
- Triage confidence is ambiguous (0.30–0.79)
- Design risk is MEDIUM or HIGH
- Tests fail after `max_retries` attempts
- `/security-audit` finds CRITICAL or HIGH vulnerabilities
- `/qa` gates fail after auto-fix attempts
- Production deployment approval is needed (always)

Respond on the GitHub issue or tracker ticket with a command:

| Comment | Effect |
|---------|--------|
| `AGENT_RESUME` | Resume from current phase (`AGENT_RESUME phase=<phase>` to pick a phase) |
| `AGENT_APPROVE_DESIGN` | Approve a medium/high-risk design |
| `AGENT_APPROVE_DEPLOY` | Approve a production deployment |
| `AGENT_CLARIFY: <text>` | Provide clarification and retry |
| `AGENT_SKIP_TASK` | Skip current sub-task |
| `AGENT_REJECT` | Decline an ambiguous triage result |
| `AGENT_REASSIGN` | Hand to a human developer |
| `AGENT_ABANDON` | Stop all work on this ticket |

Full escalation rules: [`.initium/docs/agent/escalation-protocol.md`](../../.initium/docs/agent/escalation-protocol.md).

---

## Effective Prompt Patterns

### Providing context
```
Given that we use hexagonal architecture with a domain layer that has no dependencies on
infrastructure, and we use Drizzle ORM for database access — implement X.
```

### Asking for options
```
What are three different approaches to implementing X? For each, describe the trade-offs
in terms of complexity, performance, and testability. Recommend one with justification.
```

### Requesting minimal changes
```
Make the smallest possible change to fix the failing test. Do not refactor surrounding code.
```

### Debugging with context
```
This test is failing with error: [paste error]. The function under test is [paste code].
What is the root cause? Show me the minimal fix.
```

### Keeping AI on track
```
We decided in the design step to use [approach]. Stick to that approach.
Do not introduce [pattern we rejected].
```

---

## Red Flags — Stop and Review

Stop and review carefully when AI-generated code:

- Introduces a new dependency you didn't discuss
- Uses a pattern inconsistent with the rest of the codebase
- Skips error handling for a code path
- Adds unnecessary abstraction "for future extensibility"
- Modifies files you didn't ask it to touch
- Has TODO comments that weren't discussed
- Adds a GitHub Action or container image by tag instead of a pinned digest/SHA
- Touches auth, authorization, or cryptography — always review line by line
- Produces a test that passes trivially (never actually asserts anything meaningful)

---

## All Commands — Quick Reference

`/help` prints this catalog inside your AI tool; the tables below mirror it.

### Setup and help

| Command | Purpose |
|---------|---------|
| `/help [question]` | Show all commands, or map a question to the right command sequence |
| `/init <description>` | Populate all TODO placeholders; scoped modes `domain:`, `stack:`, `ci:`, `agent:` |
| `/sync-initium [--check\|--dry-run]` | Pull the latest Initium updates into this project |

### Planning and design

| Command | Purpose |
|---------|---------|
| `/requirements <topic>` | User stories, acceptance criteria, tasks, Definition of Done |
| `/architect <feature>` | Design before coding, with a risk level |
| `/task plan\|list\|next\|done <ID>\|status` | Create and track task files in `.agent/tasks/` |
| `/sprint <theme>` | Sprint planning: capacity, backlog, risks |

### Development

| Command | Purpose |
|---------|---------|
| `/implement <task>` | Structured bottom-up implementation with tests |
| `/goal <objective>` | Pursue one objective until its Definition of Done, without stopping mid-way |
| `/refactor <target>` | Behavior-preserving refactor with a test safety net |
| `/upgrade [audit\|security\|runtime <name> <version>\|<package>]` | Audit or upgrade dependencies and runtimes |
| `/debug <issue>` | Systematic bug diagnosis: hypotheses → fix → prevention |

### Quality and review

| Command | Purpose |
|---------|---------|
| `/test <file>` | Generate comprehensive tests |
| `/qa` | Lint, types, tests, coverage, dependency CVEs, self-review |
| `/review` | Code review against standards, architecture rules, OWASP |
| `/security-audit [diff\|full\|deps\|secrets\|<path>]` | OWASP SAST + CVE + secret scan |
| `/perf <target>` | Measure, find, and fix a performance bottleneck |
| `/a11y <scope\|diff>` | Accessibility audit and fixes against WCAG 2.2 AA |
| `/eval create\|run\|compare` | Evaluation suites for LLM-powered features |

### UI and visual design

| Command | Purpose |
|---------|---------|
| `/design <screen or flow>` | Design and build UI that looks deliberate and native, not templated |
| `/design-review <scope\|diff>` | Read-only review for template tells, craft, Apple HIG / Material 3 fit |
| `/polish <scope\|diff>` | Final visual quality pass (states, spacing, consistency) |
| `/design-system [seed\|check\|tokens]` | Create or refresh `DESIGN.md` / `PRODUCT.md` and design tokens |

### Context and knowledge

| Command | Purpose |
|---------|---------|
| `/codegraph [setup\|status\|query\|impact\|refresh]` | Code graph for symbol, caller, and impact lookups |
| `/skill [new\|update\|list]` | Create, update, or list Agent Skills in `.claude/skills/` |

### Documentation

| Command | Purpose |
|---------|---------|
| `/docs <file or feature>` | Code-level docs, architecture docs, or user guides |
| `/doc-api` | Full OpenAPI 3.x spec |
| `/doc-schema` | Database schema with ER diagrams |
| `/doc-diagrams [flow\|all]` | Mermaid sequence diagrams for API and business flows |
| `/doc-site` | Scaffold or regenerate the documentation website |
| `/doc-changelog` | Generate or update `CHANGELOG.md` from git history |

### Database, infrastructure, deployment

| Command | Purpose |
|---------|---------|
| `/migrate <desc>` | Safe DB migration (Expand-Contract + rollback plan) |
| `/db init\|create\|dml\|seed\|status\|diff\|audit` | Migration tooling and database lifecycle |
| `/infra <platform> <subcommand>` | Scaffold Terraform, Kubernetes, or CI/CD configs |
| `/deploy <env>` | Pre-deploy checklist, execution, monitoring plan |

### Operations and autonomous agent

| Command | Purpose |
|---------|---------|
| `/standup` | Daily summary from git history |
| `/triage <issue>` | Domain relevance check for a tracker issue |
| `/groom` | Batch backlog processing (triage + requirements) |
| `/loop <task-id>` / `/loop resume <task-id>` | Full autonomous dev loop |
| `/escalate <severity> <trigger> <task-id>` | Structured human notification when blocked |

---

## Context Window Management

For long sessions, AI tools may lose context. Signs:
- AI suggests solutions inconsistent with the architecture
- AI contradicts earlier decisions
- AI asks for information it was given earlier

**Reset strategy:**
1. Start a new session
2. Reference key files: `@AGENTS.md`, `@docs/architecture/overview.md`, the current `.agent/tasks/TASK-*.md`
3. Briefly summarize the current task
4. Continue from where you left off

To keep sessions small in the first place: use `/codegraph query` / `/codegraph impact` instead of
reading whole files, and let skills load on demand rather than pasting stack guidance into prompts.

---

## Team Workflow

### Code Review
- PRs should note which parts were AI-generated
- Apply the same review standards to AI-generated code as human-written code
- Run `/security-audit diff` on PRs from the autonomous agent before approving

### Knowledge Sharing
- When you find an effective prompt pattern, document it in this file
- When AI makes a systematic mistake, add a rule to `.cursor/rules/` or update the matching skill with `/skill update <name>`
- When a new domain concept is introduced, update `docs/context/domain-glossary.md`
- When a security pattern recurs, add it to `.claude/skills/security-sast/SKILL.md` (or its `reference/` file for the language)
