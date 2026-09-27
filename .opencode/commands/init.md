Initialize this project from Initium by populating all TODO placeholder files based on the provided description.

This command accepts either a **full project description** (populates everything at once) or a
**targeted scope keyword** followed by the relevant details (populates only that section).

---

## Usage Modes

### Full initialization
```
/init I'm building a multi-tenant inventory management API for e-commerce merchants.
     Tech stack: TypeScript, Fastify, PostgreSQL, Drizzle ORM.
     GitHub project, Slack for alerts.
```

### Targeted initialization
```
/init domain: Order management platform handling cart, checkout, payment, and fulfilment for B2C merchants
/init stack: Go, Gin, PostgreSQL, GitHub Actions, Docker, AWS ECS
/init ci: GitHub Actions with Docker build, Jest tests, and deployment to AWS ECS via OIDC
/init agent: JIRA project key ORD, escalation via Slack #dev-alerts, GitHub owner acme/order-service
```

Multiple scopes can be combined in one call:
```
/init domain: ... | stack: ... | agent: ...
```

---

## Step 1: Parse Input

Identify the mode from `$ARGUMENTS`:

- If it starts with a known scope keyword (`domain:`, `stack:`, `ci:`, `agent:`, `glossary:`) →
  **targeted mode**: only populate the matching sections
- Otherwise → **full mode**: populate all TODO files

For **full mode**, extract these signals from the description:
- Project name (look for proper nouns at the start, or "called X", "named X")
- Project type (API / web app / CLI / library / mobile app / microservice)
- Primary language and framework
- Database and ORM
- Authentication method (if mentioned)
- Testing framework (if mentioned)
- Deployment target (if mentioned)
- Issue tracker (JIRA / Linear / GitHub Issues)
- Business domain (what the system manages)
- Core entities (nouns that represent the key data models)
- Explicit out-of-scope areas (if mentioned)

If critical information is missing for full mode (name, type, domain, primary language),
ask up to 4 targeted clarifying questions before proceeding. Do NOT ask for information
that can be reasonably inferred.

---

## Step 2: Generate File Contents

For each file, read the current content first, then replace every TODO section with
project-specific content. Preserve all existing non-TODO content, comments, and structure.

### 2a. AGENTS.md

Populate:
- `**Name:**` — project name
- `**Type:**` — project type
- `**Purpose:**` — 1–2 sentence description
- `**Primary language(s):**` — detected language(s)
- `**Framework(s):**` — detected framework(s)
- `**Runtime:**` — detected runtime
- All commands block — generate the actual commands for the detected stack:
  ```bash
  # Install: bun install / pip install -e ".[dev]" / go mod tidy / mvn install
  # Dev server: bun dev / uvicorn main:app --reload / go run ./cmd/server
  # Tests: bun test / pytest / go test ./... / mvn test
  # Lint: bun lint / ruff check . / golangci-lint run
  # Build: bun build / python -m build / go build ./...
  ```
- Repository layout — generate a plausible layout for the detected stack/pattern:
  - TypeScript API → `src/{routes,services,repositories,domain,middleware}/`
  - Python FastAPI → `app/{api,core,models,schemas,services}/`
  - Go → `cmd/server/`, `internal/{handler,service,repository,domain}/`
  - Java Spring → `src/main/java/.../`, split by `controller`, `service`, `repository`, `domain`
- Architecture bullet points — pattern, database, auth, external services, deployment
- Naming conventions — standard for the detected language
- Domain glossary — top 5–8 domain terms inferred from the description

Skip sections that cannot be reasonably populated (leave TODO with a hint comment).

---

### 2b. .cursor/rules/00-project-overview.mdc

Populate:
- `**Name:**`, `**Type:**`, `**Purpose:**`
- Technology stack table — fill all rows with detected choices
- Repository layout — same layout as generated for AGENTS.md
- Key constraints — infer from description (multi-tenancy, compliance mentions, etc.)
- Domain glossary — same terms as AGENTS.md

---

### 2c. docs/context/project-brief.md

Populate:
- "What Is This Project?" — 2–3 sentences from description
- "Who Are the Users?" — infer primary user types from the domain
- "Core Features" — list 5–7 core capabilities inferred from the domain
- "What This Project Is NOT" — infer out-of-scope areas from domain boundaries
- "Key Business Rules" — infer 3–5 key business invariants from the domain
- Leave "Success Metrics" and "Timeline & Status" as TODO (project-specific)

---

### 2d. docs/context/domain-boundaries.md

This is the most critical file for the autonomous agent. Populate:

**Project Domain Statement** — one precise sentence describing the system's responsibility scope.

**What This Project IS Responsible For:**
- Core Domains — list 3–6 specific functional areas with brief descriptions
- APIs & Interfaces — generate plausible endpoint examples matching the domain
  (e.g., `POST /v1/orders`, `GET /v1/orders/{id}` for an order management system)
- Databases / Data Owned — list the primary tables/collections based on core entities
- Typical In-Scope Request Examples — 4–5 concrete ✅ examples

**What This Project Is NOT Responsible For:**
- Out-of-Scope Domains — list 4–6 adjacent systems/teams that are explicitly out of scope
- Systems This Project Integrates With — list 3–4 external services
- Typical Out-of-Scope Request Examples — 4–5 concrete ❌ examples with suggested owners

**Ambiguous / Boundary Cases table** — generate 3–5 realistic boundary cases

**Agent Classification Guidance:**
- Keywords That Increase Domain Confidence — extract 8–15 domain-specific nouns and verbs
- Keywords That Decrease Domain Confidence — extract 6–10 adjacent-domain keywords
- Entities That Belong to This Domain — list core entity names (PascalCase)

Set `**Last reviewed:**` to today's date.

---

### 2e. docs/context/domain-glossary.md

Generate a complete glossary with 10–20 terms:
- All core entity names with definitions
- Domain-specific verbs and processes
- Any acronyms or jargon inferred from the description
- Format: `| Term | Definition | Example |`

---

### 2f. docs/context/tech-stack.md

Populate the full technology stack table:

| Category | Choice | Version | Rationale |
|----------|--------|---------|-----------|
| Language | ... | ... | ... |
| Framework | ... | ... | ... |
| Database | ... | ... | ... |
| ORM / Query builder | ... | ... | ... |
| Auth | ... | ... | ... |
| Testing | ... | ... | ... |
| CI/CD | ... | ... | ... |
| Containerisation | ... | ... | ... |
| Deployment | ... | ... | ... |

For choices that were not specified, pick the most idiomatic option for the detected language
and note it as "recommended default — confirm with team".

---

### 2g. docs/architecture/overview.md

Generate a structured architecture overview:
- System purpose and responsibilities
- Architecture pattern (infer from stack: MVC / Hexagonal / Clean / CQRS)
- ASCII block diagram of the main components and their relationships
- Data flow description (request → response trace for the primary use case)
- Key design decisions (2–4 bullets)
- Leave "Operational Concerns" and "ADR Index" for manual completion

---

### 2h. agent.config.yaml

Replace only the TODO values — do not change any non-TODO config:
- `agent.id` → `"<project-slug>-agent"` (slugify the project name)
- `agent.name` → `"<Project Name> Dev Agent"`
- `issue_tracker.provider` → detected tracker (default: `github` if not specified)
- `jira.project_key` → from `agent:` scope input, or leave TODO
- `jira.backlog_jql` → replace `project = "TODO"` with actual key if known
- `linear.team_id` → from `agent:` scope input, or leave TODO
- `github.owner` and `github.repo` → from `agent:` scope input, or leave TODO
- `domain.strong_include_keywords` → array of in-domain keywords from domain analysis
- `domain.hard_exclude_keywords` → array of out-of-scope keywords
- `escalation.github.assignees` → from `agent:` scope input, or leave TODO
- `escalation.email.to` → from `agent:` scope input, or leave TODO

---

### 2i. .github/workflows/ci.yml (targeted with `ci:` scope only)

Generate real CI job steps for the detected stack:

**lint job:**
```yaml
- uses: actions/setup-node@v4       # or setup-python, setup-go, etc.
  with: { node-version: '22' }
- run: bun install                   # actual install command
- run: bun lint                      # actual lint command
```

**test job:**
```yaml
- run: bun test --coverage
- uses: codecov/codecov-action@v4
```

**security job:**
```yaml
- uses: aquasecurity/trivy-action    # or snyk, dependabot, etc.
- run: npm audit --audit-level=high
```

**build job:**
```yaml
- run: bun build                     # or: docker build, mvn package, etc.
- uses: docker/build-push-action     # if Docker deployment detected
```

Only generate this section when `ci:` scope is explicitly requested, or as part of full init
when the deployment target is clear enough to generate accurate steps.

---

## Step 3: Write All Generated Files

For each file, write the populated content back. Report each write:
```
✅ AGENTS.md — populated (12 TODO items resolved)
✅ .cursor/rules/00-project-overview.mdc — populated
✅ docs/context/project-brief.md — populated
✅ docs/context/domain-boundaries.md — populated (critical for agent triage)
✅ docs/context/domain-glossary.md — generated (18 terms)
✅ docs/context/tech-stack.md — populated
✅ docs/architecture/overview.md — generated
⚠️  agent.config.yaml — partially populated (3 TODO items remain: JIRA key, Linear team ID, email recipients)
⚠️  .github/workflows/ci.yml — skipped (use /init ci: <stack> to generate CI steps)
```

---

## Step 4: Validation

After writing all files, run:
```bash
bash .initium/scripts/validate.sh 2>/dev/null | grep -E "FAIL|WARN.*TODO"
```

Report remaining TODO items grouped by file.

---

## Step 5: Summary

```
╔══════════════════════════════════════════════════════════════╗
║  PROJECT INITIALIZED: <Project Name>                        ║
╠══════════════════════════════════════════════════════════════╣
║  Files populated:  N                                        ║
║  TODOs resolved:   N                                        ║
║  TODOs remaining:  N (listed above)                         ║
╠══════════════════════════════════════════════════════════════╣
║  NEXT STEPS:                                                ║
║  1. Review generated content — AI inference is not perfect  ║
║  2. Fill remaining TODOs (listed above)                     ║
║  3. Add API keys to .env and .continue/config.yaml          ║
║  4. Run: bash .initium/scripts/validate.sh                 ║
║  5. Start coding: /requirements <your first feature>        ║
╚══════════════════════════════════════════════════════════════╝
```

---

Project description or targeted scope:

$ARGUMENTS
