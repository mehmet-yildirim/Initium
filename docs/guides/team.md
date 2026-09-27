# Team Formation Guide — AI-Native Development

This guide defines how human teams should be structured and optimized when working with Initium. The AI tools handle boilerplate, repetition, and mechanical reasoning — the team's job is judgment, context, and oversight.

> **Turkish / Türkçe:** [docs/guides/team.tr.md](team.tr.md) — Türkçe takım oluşturma kılavuzu

> **Fill in the TODO sections** with your project-specific people and contacts.

---

## Core Principle: Fewer, More Focused Engineers

AI multiplies individual productivity. A small team of 3–6 engineers with clear ownership, deep domain knowledge, and strong AI collaboration skills consistently outperforms a larger traditional team on this stack.

**Shift your team's effort:**

| Traditional team spends time on | AI-native team spends time on |
|---------------------------------|-------------------------------|
| Writing boilerplate and scaffolding | Reviewing AI-generated code critically |
| Searching docs and Stack Overflow | Validating AI reasoning and output |
| Mechanical refactoring | Architecture decisions and domain modeling |
| Repetitive test writing | Designing meaningful test scenarios |
| Writing first drafts of documentation | Verifying and refining AI-generated docs |

The ratio of senior to junior engineers shifts: **prefer senior or mid-level engineers** who can evaluate AI output confidently. Junior engineers need stronger mentorship to avoid accepting AI output uncritically.

---

## Team Roles

### Tech Lead / Architect

**What they do:**
- Own `docs/architecture/overview.md` and all ADRs in `docs/architecture/decisions/`
- Define and enforce the hexagonal architecture boundaries and design pattern standards
- Approve high-risk designs flagged by `/architect` (triggered by `risk=HIGH`)
- Review autonomous agent PRs before merge for any structural changes
- Maintain `AGENTS.md` — the single source of truth for how AI agents understand this project
- Decide when to adopt new Initium features via `/sync-initium`

**AI-native responsibilities:**
- Set `AGENT_APPROVE_DESIGN` on JIRA/GitHub when the autonomous agent escalates architecture decisions
- Block merges of AI-generated code that violates layer boundaries or introduces inappropriate patterns
- Review the agent's `docs/guides/agent/` configuration and tuning

**TODO: Assigned to:** `<name>`

---

### Domain Owner(s)

**What they do:**
- Maintain `docs/context/domain-boundaries.md` — the most critical file for autonomous agent triage
- Define which JIRA/Linear/GitHub issues are in scope, and which belong to other teams
- Maintain `docs/context/domain-glossary.md` so the agent uses correct terminology
- Respond to `/escalate` notifications when the agent is uncertain about domain relevance (triage confidence 0.30–0.79)

**AI-native responsibilities:**
- Post `AGENT_CLARIFY: <explanation>` on escalated tickets to guide the agent
- Review triage decisions regularly — if the agent is mis-classifying issues, update `domain-boundaries.md`
- Own the domain model; AI proposes, domain owner approves

**One domain owner per bounded context is the target. On small teams, the Tech Lead doubles as Domain Owner.**

**TODO: Domain owners by area:**
- `<domain area>` → `<name>`
- `<domain area>` → `<name>`

---

### Senior / Mid-Level Developer

**What they do:**
- Use AI tools (`/requirements`, `/architect`, `/implement`, `/qa`, `/review`) for day-to-day feature development
- Read and critically evaluate every line of AI-generated code before committing
- Write acceptance criteria and task descriptions detailed enough for `/implement` to execute correctly
- Own the quality of the branch they open — AI generates, human verifies

**AI-native responsibilities:**
- Run `/security-audit diff` on every PR without exception
- Run `/qa` before opening PRs; do not open PRs with failing gates
- When AI output is wrong, fix the code AND update the relevant rule in `.cursor/rules/` or AGENTS.md so the error doesn't recur
- Share effective prompt patterns in `docs/guides/ai-workflow.md` under "Effective Prompt Patterns"

**TODO: Team members:** `<list names or link to team roster>`

---

### AI Workflow Coordinator

**What they do:**
- Keep all AI tooling running smoothly across the team
- Run `/sync-initium` when Initium updates are available; coordinate merging `merge_required` files with the team
- Maintain `.cursor/rules/`, `.continue/rules/`, and AGENTS.md conventions
- Track which commands are underused or causing confusion; improve prompts or document patterns
- Manage `.cursor/mcp.json` and `.claude/settings.json` — enable/disable MCP servers and tool permissions
- Own `agent.config.yaml` tuning: confidence thresholds, retry limits, autonomous mode settings

**This role does not need to be a separate headcount.** On a team of 3–5, the Tech Lead or a senior developer rotates into this role. On larger teams (8+), dedicate 20–30% of one engineer's time to it.

**AI-native responsibilities:**
- Monitor autonomous agent audit logs in `.agent/audit/` for unexpected behavior
- Tune triage confidence thresholds when the agent over- or under-accepts issues
- Review and test Initium updates before rolling them out to the team

**TODO: Assigned to:** `<name>`

---

### Security Champion

**What they do:**
- Run periodic `/security-audit full` scans (weekly or per release)
- Review all `CRITICAL` and `HIGH` findings from any PR's `/security-audit diff`
- Maintain the OWASP checklist and security rules in `.cursor/rules/05-security.mdc`
- Approve deployment of any PR that had a HIGH finding, even if resolved

**AI-native responsibilities:**
- The autonomous agent runs `/security-audit` automatically — the Security Champion reviews the generated reports, not just the code
- When AI introduces a new security pattern (good or bad), update `.claude/skills/security-sast/SKILL.md` to reinforce or prevent it
- Block `AGENT_APPROVE_DEPLOY` for any production deployment with unreviewed security findings

**On small teams, the Tech Lead or most security-aware developer fills this role.**

**TODO: Assigned to:** `<name>`

---

## Decision Authority Matrix

Clear ownership prevents the agent from proceeding without the right human approving the right decision.

| Decision | Who decides | Autonomous agent trigger |
|----------|-------------|--------------------------|
| Architecture approach (high-risk) | Tech Lead | `/escalate` → `AGENT_APPROVE_DESIGN` |
| Domain boundary (is this issue in scope?) | Domain Owner | `/escalate` → `AGENT_CLARIFY:` |
| Production deployment | Tech Lead + Security Champion | `/escalate` → `AGENT_APPROVE_DEPLOY` |
| CRITICAL security finding | Security Champion | `/escalate` → blocks deploy |
| Merge to main (automated PR) | Any senior dev reviewer | GitHub PR review |
| Initium update (merge_required files) | AI Workflow Coordinator | `/sync-initium` review |
| Agent abandon / reassign | Domain Owner or Tech Lead | `AGENT_REASSIGN` or `AGENT_ABANDON` |

---

## Team Size Recommendations

### 1–3 people (solo / micro team)

- Tech Lead does everything: architecture, domain ownership, AI workflow coordination
- Use semi-autonomous agent mode (`mode: semi-autonomous` in `agent.config.yaml`) — agent generates, human approves before every PR
- Every PR must be reviewed by at least one other person (external reviewer or peer)
- Prioritize: `AGENTS.md` quality, domain boundaries accuracy, security audit before every merge

### 3–6 people (standard team)

- Tech Lead owns architecture + escalation approvals
- 1–2 developers own specific domain areas
- Rotate the AI Workflow Coordinator role quarterly
- Security Champion role assigned to most security-aware developer (part-time)
- Agent can run in semi-autonomous or selective-autonomous mode per domain
- Weekly 30-minute "AI workflow retrospective": what worked, what the agent got wrong, what rules need updating

### 7–15 people (scaled team)

- Full role separation: Tech Lead, 2–3 Domain Owners, dedicated AI Workflow Coordinator (part-time), Security Champion
- Introduce a **platform sub-team** (1–2 people) that owns Initium, MCP servers, and agent infrastructure
- Each domain owner manages their area's `domain-boundaries.md` entries
- Agent runs in full autonomous mode for accepted, low-risk issues
- Bi-weekly architecture review meeting: Tech Lead + domain owners review agent ADRs
- Cross-team: if multiple teams share a monorepo, each team has its own domain boundaries and triage scope

---

## Onboarding a New Team Member

For new engineers to become productive quickly:

1. **Day 1 — Context reading:** Read `docs/context/project-brief.md`, `docs/context/tech-stack.md`, `docs/architecture/overview.md`, and this file. Then `AGENTS.md`.
2. **Day 1 — AI tools setup:** Follow `docs/guides/onboarding.md` to install Claude Code, configure Cursor or Continue. Verify with `bash .initium/scripts/validate.sh`.
3. **Day 2 — First `/help`:** Run `/help how do I pick up my first task?` and follow the instructions. Don't start writing code before completing the AI workflow setup.
4. **First week — shadowed PR:** New engineer implements a `good-first-issue` using the full AI loop (`/requirements` → `/architect` → `/task plan` → `/implement` → `/qa` → `/review`). A senior dev reviews every step, not just the final diff.
5. **First month — no autonomous mode:** New engineers use human-guided commands only. Autonomous mode (`/loop`) after they can confidently review AI output.

**Key mindset to instil early:** The AI is a capable collaborator, not an oracle. Read every generated line. Question every pattern. The human is responsible for the output.

---

## Anti-Patterns to Avoid

| Anti-pattern | Why it fails |
|---|---|
| Merging AI PRs without reading the diff | AI can introduce subtle bugs, wrong patterns, or security issues that look fine at a glance |
| Skipping `/security-audit diff` because "AI is usually safe" | AI frequently misses auth checks, input validation, and injection risks |
| Letting the agent run autonomously without domain boundaries defined | Agent will accept out-of-scope issues and produce irrelevant or harmful changes |
| Treating AGENTS.md as a one-time setup | Project evolves; AGENTS.md must be updated when conventions change or the agent makes systematic errors |
| Using AI for architecture decisions without human review | Architecture is about tradeoffs the AI cannot fully evaluate — business context, team capability, operational cost |
| Not updating `.cursor/rules/` when AI makes a pattern mistake | The mistake will recur in every future session |
| Over-automating too early | Start semi-autonomous, earn trust in the agent's triage accuracy before enabling full autonomy |

---

## Further Reading

| Document | Contents |
|----------|---------|
| `AGENTS.md` | Project conventions — the AI's primary instruction file |
| `docs/guides/ai-workflow.md` | Full AI-native development workflow reference |
| `docs/guides/onboarding.md` | Step-by-step setup for new developers |
| `docs/context/domain-boundaries.md` | What the autonomous agent will and will not work on |
| `docs/guides/agent/autonomous-workflow.md` | Agent state machine, escalation gates, resume logic |
| `docs/guides/agent/escalation-protocol.md` | Escalation severity levels and human response procedures |
| `agent.config.yaml` | Autonomous agent configuration — mode, thresholds, tracker keys |
