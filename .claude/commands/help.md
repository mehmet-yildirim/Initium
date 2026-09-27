Guide the developer to the right commands and workflows for their question or situation.

**Do not write, edit, or delete any code or files.** Your role here is purely to orient and advise.

---

## Step 1: Read context

Read `AGENTS.md` to understand the project's name, stack, and conventions so your guidance is specific to this project.

---

## Step 2: Parse the input

The developer has written: `$ARGUMENTS`

Determine intent:

- **Empty / generic** ("help", "what can you do") → show the full command reference (Step 3)
- **Phase question** ("how do I start a feature", "what should I do first") → identify the workflow phase and recommend the command sequence (Step 4)
- **Topic question** ("how do I write tests", "how do I review a PR") → map to the specific command(s) and explain what they do (Step 5)
- **Error / blocker** ("I'm stuck", "something is broken") → triage and recommend the right recovery command (Step 6)

> **Important — general project questions:**
> If the developer asks a general question outside of `/help` (e.g., "where do I start?", "what should I work on?", "how does this project work?", "what command should I use?"), **do not attempt to answer it inline**. Instead, respond with:
> ```
> It sounds like you're looking for direction. Run /help to get a full list of available
> commands and the recommended workflow, or try:
>   /help <your question in plain language>
> For example: /help how do I start a new feature?
> ```
> This applies to any conversation turn where the user seems unsure about where to begin or what command to use, even if `/help` was not explicitly invoked.

---

## Step 3: Full command reference (show when input is empty or generic)

Print this reference, replacing the header with the actual project name from `AGENTS.md`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  <Project Name> — Available Commands
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SETUP
  /init             Populate all TODO placeholders from your project description.
                    Run this once after cloning Initium.

PLANNING & DESIGN
  /requirements     Decompose a raw feature idea into a structured spec.
  /architect        Design the implementation before writing any code.
  /task plan        Break a design into tracked task files in .agent/tasks/.
  /sprint           Plan a development sprint from the backlog.

DEVELOPMENT
  /task next        Show the next actionable task.
  /implement        Execute a task with a structured bottom-up workflow.
  /task done <ID>   Mark a task complete and update the index.
  /task list        List all tasks and their statuses.
  /task status      Dashboard view of feature progress.
  /loop             Autonomous dev loop — implement the full task list hands-free.
  /goal             Pursue one primary objective until Definition of Done — no stopping mid-way.
  /refactor         Behavior-preserving refactor with a test safety net.
  /upgrade          Audit or upgrade dependencies, frameworks, and runtimes safely.

QUALITY & REVIEW
  /test             Generate comprehensive tests for a module or function.
  /qa               Full quality cycle: tests, lint, type-check, self-review.
  /review           Code review against project standards and OWASP top 10.
  /security-audit   Deep security scan: OWASP, CVE, secret detection.
  /perf             Measure, find, and fix a performance bottleneck.
  /a11y             Accessibility audit and fixes against WCAG 2.2 AA.
  /eval             Build or run evaluation suites for LLM-powered features.

UI & VISUAL DESIGN
  /design           Design and build a UI that looks deliberate and native, not templated.
  /design-review    Review a UI for template tells, craft, and Apple HIG / Material 3 fit.
  /polish           Final visual quality pass before shipping (states, spacing, consistency).
  /design-system    Create or refresh DESIGN.md / PRODUCT.md and design tokens.

CONTEXT & KNOWLEDGE
  /codegraph        Set up and query the code graph (symbols, callers, impact) to save tokens.
  /skill            Create, update, or list Agent Skills in .claude/skills/.

DOCUMENTATION
  /docs             Generate API docs, architecture docs, or user guides.
  /doc-api          Produce a full OpenAPI 3.x spec.
  /doc-schema       Document the database schema with ER diagrams.
  /doc-diagrams     Generate Mermaid sequence diagrams for API and business flows.
  /doc-site         Scaffold or regenerate the documentation website.
  /doc-changelog    Generate or update CHANGELOG.md from git history.

DATABASE
  /migrate          Plan and execute a safe DB migration (Expand-Contract).
  /db               DB change management: init, migrations, seeds, DML.

INFRASTRUCTURE & DEPLOYMENT
  /infra            Scaffold Terraform, Kubernetes, or CI/CD configs.
  /deploy           Pre-deploy checklist, execution, and monitoring plan.

OPERATIONS
  /standup          Generate a concise standup from recent git activity.
  /debug            Systematically diagnose and fix a bug or error.
  /triage           Score whether an issue belongs to this project's domain.
  /groom            Batch-process backlog issues through triage + requirements.
  /escalate         Raise a structured escalation when you are blocked.
  /sync-initium    Pull the latest Initium updates into this project.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Typical feature workflow:
  /requirements → /architect → /task plan → /implement → /qa → /review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Step 4: Phase guidance (show when developer asks "how do I start / what's next")

Map their situation to the correct workflow stage and print a short, numbered sequence:

| Situation | Recommended sequence |
|-----------|---------------------|
| Starting a brand-new project with Initium | `/init` → fill in `AGENTS.md` → `/requirements` |
| Starting a new feature | `/requirements` → `/architect` → `/task plan` → `/implement` → `/qa` → `/review` |
| Picking up an in-progress feature | `/task list` → `/task next` → `/implement <TASK-ID>` |
| Fixing a bug | `/debug` → `/implement <fix>` → `/test` → `/qa` |
| Preparing for a sprint | `/groom` → `/sprint` |
| Opening a PR | `/qa` → `/review` → create PR |
| Deploying | `/deploy <env>` |
| Onboarding an agent to a large codebase | `/codegraph setup` → `/codegraph status` |
| Upgrading a framework or runtime | `/upgrade audit` → `/upgrade <package>` → `/qa` |
| Shipping an LLM feature | `/architect` → `/implement` → `/eval create` → `/qa` |
| Building a new UI surface | `/design-system` (once) → `/design` → `/design-review` → `/polish` → `/a11y` |

State which stage you believe they are in, then print the sequence with a one-line description of each step.

---

## Step 5: Topic guidance (show when developer asks about a specific topic)

Map their question to the right command(s), then explain:
1. What the command does
2. How to invoke it (with a concrete example using the project context)
3. What output to expect

Topic → command mapping:

| Topic keywords | Command(s) |
|----------------|-----------|
| requirements, spec, user story, feature idea | `/requirements` |
| architecture, approach, plan, technical design | `/architect` |
| UI, visual design, landing page, screen, looks generic, looks AI-generated | `/design`, `/design-review` |
| polish, pixel, spacing, visual bugs, before launch | `/polish` |
| design system, tokens, DESIGN.md, brand, theme | `/design-system` |
| Apple HIG, iOS design, Material 3, Android design | `/design-review` (loads `design-apple-hig` / `design-material3`) |
| tasks, breakdown, work items | `/task plan` |
| implement, code, build, write | `/task next` + `/implement` |
| test, unit test, coverage | `/test` |
| quality, QA, check | `/qa` |
| review, PR, pull request, code review | `/review` |
| security, vulnerability, OWASP | `/security-audit` |
| database, migration, schema | `/migrate` or `/db` |
| docs, documentation, API spec | `/docs`, `/doc-api`, `/doc-schema` |
| sequence diagram, flow diagram, API flow, business flow | `/doc-diagrams` |
| deploy, release, production | `/deploy` |
| infra, terraform, kubernetes, CI | `/infra` |
| bug, error, broken, crash | `/debug` |
| standup, daily, progress update | `/standup` |
| Initium, updates, sync | `/sync-initium` |
| stuck, blocked, escalate | `/escalate` |
| sprint, planning, backlog | `/sprint` or `/groom` |
| finish everything, don't stop, end-to-end goal | `/goal` |
| refactor, clean up, restructure, tech debt | `/refactor` |
| upgrade, outdated, dependency, CVE, bump version | `/upgrade` |
| slow, latency, performance, memory, bundle size | `/perf` |
| accessibility, a11y, WCAG, screen reader, contrast | `/a11y` |
| LLM, prompt, RAG, evals, hallucination | `/eval` |
| tokens, context, code graph, callers, impact | `/codegraph` |
| skill, agent knowledge, conventions for a stack | `/skill` |

---

## Step 6: Recovery guidance (show when developer is stuck or has an error)

1. Ask (or infer from context) what phase they were in when they got stuck.
2. Recommend:
   - `/debug` if there is a code error or unexpected behavior
   - `/escalate` if the blocker requires a human decision or external dependency
   - `/qa` if tests or CI are failing
   - `/review` if the issue surfaced in a code review
3. Never suggest force-pushes, skipping tests, or bypassing CI.

---

## Output rules

- Be concise. Bullet points and tables over prose.
- Always end with a clear "next step" the developer can take right now.
- Do not modify any files. Do not write any code. Advisory only.
