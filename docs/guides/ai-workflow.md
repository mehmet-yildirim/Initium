# AI-Native Development Workflow

This document describes how to work effectively with AI tools in this project.
Following this workflow produces faster, higher-quality results.

> **Türkçe:** [docs/guides/ai-workflow.tr.md](ai-workflow.tr.md) — Türkçe sürüm için bakın.

---

## The AI-Native Loop

```
1. CONTEXT   → Give AI the right information before asking for code
2. DESIGN    → Have AI design before it codes       (/architect)
3. IMPLEMENT → Implement with AI in small steps     (/implement)
4. SECURITY  → Evaluate every change for risks      (/security-audit)
5. REVIEW    → Review AI output critically          (/review)
6. TEST      → Generate and run tests              (/test)
7. DOCUMENT  → Update docs while context is fresh  (/docs)
```

### Autonomous Mode (agent drives the loop)

```
JIRA backlog ──▶ /triage ──▶ /groom ──▶ /loop ──▶ PR ──▶ /deploy
                   │                      │
             domain check          full loop per task:
             accept/reject         architect → implement →
                                   security-audit → qa → PR
```

---

## Tool Overview

| Tool | Best for | Key config |
|------|----------|-----------|
| **Claude Code** | Complex agentic tasks, multi-file edits, CLI | `AGENTS.md`, `.claude/commands/` |
| **Cursor** | In-editor generation, chat, autocomplete | `.cursor/rules/`, `.cursor/mcp.json` |
| **Continue** | Inline edits, chat, autocomplete in any IDE | `.continue/config.yaml` |

---

## Human-Guided Workflow

### Step 1: Provide Context First

AI tools work best when they understand your project. Context is provided via:

- **`AGENTS.md`** — Project overview, commands, conventions (read natively by Cursor, OpenCode, Codex, Copilot; Claude Code loads it through the `@AGENTS.md` import in `CLAUDE.md`)
- **`.cursor/rules/`** — Persistent rules loaded for every Cursor interaction (auto by file type)
- **`.continue/rules/`** — Rules included in every Continue request
- **`docs/context/`** — Deeper project context you can reference with `@docs`

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

### Step 4: Implement in Small Steps

Use `/implement` with one task at a time — not the entire feature at once.

```
/implement TASK-001: Create PasswordReset entity and repository interface
/implement TASK-002: Implement RequestPasswordReset use case
/implement TASK-003: Add POST /auth/password-reset endpoint
```

After each step:
- **Read and understand the generated code** — never accept code you don't understand
- Run the linter and type checker
- Run the tests for the changed module

---

### Step 5: Security Evaluation

Run `/security-audit` on every change that touches auth, user input, payments, or data access:

```
/security-audit diff          # scan only changes in this branch
/security-audit src/payments/ # scan a specific directory
```

**Never open a PR with a CRITICAL security finding.**

For scheduled or full scans:
```
/security-audit full          # entire codebase
/security-audit deps          # CVE scan only
```

---

### Step 6: Quality Assurance

```
/qa
```

Runs: lint → type check → tests → coverage → dependency CVE → security summary.
Fix all blocking issues before opening a PR.

---

### Step 7: Code Review

```
/review
```

Checks the diff against project standards, architecture rules, and OWASP patterns.
Address every raised issue or explicitly mark it "won't fix" with a reason.

---

### Step 8: Generate Tests

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

---

## Autonomous Agent Workflow

The agent drives the full loop without manual intervention for each step.
See `docs/guides/agent/autonomous-workflow.md` for the full state machine.

### Starting the agent

```bash
# Process the full backlog (triage + requirements analysis)
/groom

# Execute a specific accepted task end-to-end
/loop PROJ-42

# Resume a task that was interrupted
/loop resume PROJ-42
```

### What the agent does automatically

```
/groom          → polls JIRA → triages each issue → runs /requirements on accepted ones
/triage         → domain relevance scoring → ACCEPT / ESCALATE / REJECT
/loop           → /architect → create branch → /implement (retry loop) →
                  /security-audit → /qa → create PR → monitor CI →
                  /deploy staging → monitor post-deploy
/escalate       → notifies Slack/GitHub when agent cannot proceed
```

### When the agent stops and waits for you

The agent escalates (pauses + notifies) when:
- Triage confidence is ambiguous (0.30–0.79)
- Design risk is HIGH
- Tests fail after `max_retries` attempts
- `/security-audit` finds CRITICAL or HIGH vulnerabilities
- `/qa` gates fail after auto-fix attempts
- Production deployment approval is needed (always)

Respond on the GitHub issue or JIRA ticket with a command:

| Comment | Effect |
|---------|--------|
| `AGENT_RESUME` | Resume from current phase |
| `AGENT_APPROVE_DESIGN` | Approve high-risk design |
| `AGENT_CLARIFY: <text>` | Provide clarification and retry |
| `AGENT_SKIP_TASK` | Skip current sub-task |
| `AGENT_REASSIGN` | Hand to a human developer |
| `AGENT_ABANDON` | Stop all work on this ticket |

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
- Touches auth, authorization, or cryptography — always review line by line
- Produces a test that passes trivially (never actually asserts anything meaningful)

---

## All Commands — Quick Reference

### Human-Guided

| Command | Purpose | When |
|---------|---------|------|
| `/requirements <topic>` | User stories, tasks, DoD | Before any feature |
| `/architect <feature>` | Design before coding | Tasks > 50 lines |
| `/implement <task>` | Structured implementation | During coding |
| `/security-audit [target]` | OWASP + CVE + secret scan | Before every PR |
| `/qa` | Lint, types, tests, coverage | Before opening PR |
| `/review` | Code review vs. standards | After implementation |
| `/test <file>` | Generate comprehensive tests | After any module |
| `/debug <issue>` | Systematic bug diagnosis | When stuck |
| `/deploy <env>` | Pre-deploy checklist | Before every deploy |
| `/migrate <desc>` | Safe DB migration | For schema changes |
| `/sprint <theme>` | Sprint planning | Sprint kickoff |
| `/docs <file>` | Generate documentation | After a module |
| `/standup` | Daily summary from git | Start of day |

### Autonomous Agent

| Command | Purpose | When |
|---------|---------|------|
| `/triage <issue>` | Domain relevance check | Per JIRA issue |
| `/groom` | Batch backlog processing | Scheduled / on demand |
| `/loop <task-id>` | Full autonomous dev loop | Per accepted task |
| `/escalate <sev> <trigger> <task>` | Human notification | When agent is blocked |

---

## Context Window Management

For long sessions, AI tools may lose context. Signs:
- AI suggests solutions inconsistent with the architecture
- AI contradicts earlier decisions
- AI asks for information it was given earlier

**Reset strategy:**
1. Start a new session
2. Reference key files: `@AGENTS.md`, `@docs/architecture/overview.md`
3. Briefly summarize the current task
4. Continue from where you left off

---

## Team Workflow

### Code Review
- PRs should note which parts were AI-generated
- Apply the same review standards to AI-generated code as human-written code
- Run `/security-audit diff` on PRs from the autonomous agent before approving

### Knowledge Sharing
- When you find an effective prompt pattern, document it in this file
- When AI makes a systematic mistake, add a rule to `.cursor/rules/` or `.continue/rules/`
- When a new domain concept is introduced, update `docs/context/domain-glossary.md`
- When a security pattern recurs, add it to `.claude/skills/security-sast/SKILL.md`
