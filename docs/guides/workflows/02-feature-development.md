# Workflow: Feature Development

The end-to-end AI-assisted workflow for implementing a feature from approved specification to merged PR.

## Prerequisites

Before starting development:
- [ ] Approved specification exists (see `01-requirements-analysis.md`)
- [ ] Task is sized S or M (L tasks need to be split into multiple PRs)
- [ ] Branch created: `git checkout -b feat/PROJ-42-feature-name`
- [ ] Local environment running and tests passing on main

## The Workflow

```
Approved Spec
    │
    ├─ Step 1: Design          /architect → docs/architecture/decisions/NNNN-*.md
    ├─ Step 2: Task Planning   /task plan → .agent/tasks/*.md + INDEX.md
    ├─ Step 3: Implement       /task next → /implement <TASK-ID> → code + tests
    ├─ Step 4: QA              /qa → quality gates
    ├─ Step 5: Self-Review     /review → final check
    └─ Step 6: PR & Merge      → deployed to staging
```

### Three ways to drive this workflow

| Mode | Command | Use when |
|------|---------|----------|
| Step by step (default) | the commands above, one at a time | You want to review and approve each step |
| Goal pursuit | `/goal <objective>` (resume: `/goal resume <slug>`) | One clear objective you want finished end-to-end in a session; the agent picks the planning path, runs `/implement` → `/qa`, and stops only at escalation gates |
| Autonomous | `/loop <task-id>` (resume: `/loop resume <task-id>`) | A groomed issue with `.agent/outputs/<task-id>-requirements.json`; the agent runs design → tasks → PR → CI → deploy with human approval gates (see [Autonomous Workflow](../../../.initium/docs/agent/autonomous-workflow.md)) |

`/goal` checkpoints progress in `.agent/goals/<slug>.json`; `/loop` reads `.agent/tasks/` when it
exists and calls `/task done` after each task. Both honor the `.agent/STOP` kill switch.

## Step 1: Design (/architect)

For any implementation > 50 lines of net-new code:

```
/architect <paste task description from approved spec>
```

`/architect` writes the design to `docs/architecture/decisions/NNNN-<feature>.md` with status
`Draft`. For a new UI surface, also run `/design <target>` (after `/design-system` once per project)
so the visual direction is agreed before building.

Review the design output. Approve before coding:
- Does the approach fit our architecture (layer boundaries, patterns)?
- Are all edge cases in the spec covered by the design?
- Is the implementation checklist complete and correctly ordered?
- Are there risks that need escalation?

**Rule**: Do not write production code until the design is approved.

## Step 2: Task Planning (/task plan)

After the design is approved, materialize the implementation checklist into individual task files:

```
/task plan docs/architecture/decisions/NNNN-<feature>.md
```

Without an argument, `/task plan` looks for `.agent/outputs/<task-id>-design.json`, then
`.agent/outputs/<task-id>-requirements.json`; you can also paste a checklist.

This creates `.agent/tasks/TASK-001-<slug>.md` files — one file per task — plus
`.agent/tasks/INDEX.md` with the execution order. Each task file has:
- Status (`todo` / `in_progress` / `done`)
- Type, layer, and estimate (XS–L; XL tasks must be split first)
- Acceptance criteria
- Files to change
- Dependencies (`depends_on`: which tasks must be done first)

**Why this step matters:**
- Gives you a clear, trackable work breakdown before touching code
- Enables bit-by-bit implementation — complete one task, commit, then move to the next
- Allows resuming mid-feature: check `status` to see where you left off
- In autonomous mode, the `/loop` command reads task files to drive execution

```
/task list     # every task with its status (done / in progress / blocked / todo)
/task status   # progress dashboard: current, next up, blocked
/task next     # the first actionable task (todo, all dependencies done)
```

**Rule**: For features with ≥ 3 tasks, always create task files before implementing.
Single-task fixes may skip this step.

## Step 3: Implement (/implement) — Per Task

Work through tasks one at a time in dependency order:

```
/task next              # find the next actionable task
/implement TASK-001     # implement it; /implement marks the task done and updates INDEX.md
/task next              # get the next one
```

If you implemented or finished a task outside `/implement` (by hand, or after fixing review
comments), mark it yourself with `/task done TASK-001`. When every task is done, `/task next`
reports "All tasks complete" — move on to `/qa`.

### Implementation discipline
- Implement bottom-up: types → domain logic → data access → service → API/UI
- Work task by task — do not start the next task until the current one compiles and its tests pass
- Write tests for each layer as you implement it — do not defer testing
- Keep each step small enough to compile and run tests
- Commit each completed task with a conventional commit: `git commit -m "feat(users): add CreateUser use case"`
- Restructuring existing code? Use `/refactor` — refactors and behavior changes never share a commit
- Schema change? Plan it with `/migrate` (see [Database Migrations](06-database-migrations.md))
- Dependency or framework bump needed? Use `/upgrade <package>` in its own commit

### Working with AI during implementation
- Give AI one task at a time — not the entire feature at once
- After each generated file, read every line. Do not merge code you don't understand.
- If AI goes off-track (wrong pattern, unnecessary abstraction): stop and correct immediately
- Use `@filename` in Cursor / Continue to provide context from related files
- If `codegraph.enabled` is `true`, `/implement` locates affected symbols through the code graph
  first; use `/codegraph impact <symbol>` yourself before changing widely used code
- Stack-specific conventions come from skills in `.claude/skills/` (loaded automatically when the
  task touches that stack — see the [skills index](../../../skills/README.md))

### When AI output needs correction
```
"That approach doesn't match our architecture. We use repository pattern, not direct DB calls
in the service. Re-implement the UserService using the UserRepository interface."
```

## Step 4: QA (/qa)

Before creating a PR, run the full QA cycle:

```
/qa
```

This checks: lint, type safety, tests and coverage, security (including dependency audit),
code quality, API contract, and obvious performance problems (N+1 queries, missing indexes).

Add the targeted checks that match the change:

| Change touches | Also run |
|----------------|----------|
| Auth, payments, external input, new dependencies | `/security-audit` (see [Security Evaluation](05-security-evaluation.md)) |
| UI | `/design-review`, `/polish`, `/a11y` |
| LLM prompts, RAG, agents | `/eval run <feature>` |
| Hot paths or a latency/size target | `/perf` |
| Public API or documented behavior | `/doc-api`, `/docs`, `/doc-diagrams` as needed |

**Block yourself from opening a PR if:**
- Any test fails
- Lint errors exist
- Type errors exist
- Coverage dropped below threshold
- Any CRITICAL security finding

## Step 5: Self-Review (/review)

```
/review
```

`/review` checks the branch against `AGENTS.md` and `.cursor/rules/*.mdc` and reports issues as
Critical / Major / Minor / Suggestion. Address each issue before opening the PR.
Also run a personal diff review:

```bash
git diff origin/main...HEAD
```

Ask yourself for each change:
- Do I understand why this line exists?
- Would I be comfortable explaining this in a code review?
- Is this the simplest solution?

## Step 6: PR Creation

```bash
gh pr create --fill
```

The PR template will prompt for: summary, type of change, test instructions, checklist.

**PR description must include:**
- Link to the spec or ticket
- Summary of what was built
- How to test it manually
- Any deployment notes (migrations, config changes, feature flags)

### PR Size Rules
- Aim for < 400 lines changed
- If larger: split into stacked PRs (infrastructure PR first, then feature PR)
- Large PRs slow down review and increase merge conflict risk

## Parallel Development Patterns

### Stacked PRs (feature → depends on → infrastructure)
```
main
  └─ feat/users-repo          # PR 1: repository + DB migration
       └─ feat/users-service  # PR 2: service layer (depends on PR 1)
            └─ feat/users-api # PR 3: API endpoint (depends on PR 2)
```

### Feature flags for long-running features
- Merge incomplete features behind a flag to keep branches short-lived
- Enable flag in dev; only enable in production when ready to release

## Handling Blockers

If blocked during implementation:
1. Use `/debug` for technical issues
2. Use `/architect` to reconsider the approach
3. Document the blocker and ask for help — do not keep trying the same thing
4. Timebox spikes: if blocked for > 2 hours, raise it with `/escalate <severity> <trigger> <task-id>`

## Definition of "Implementation Complete"

- [ ] All acceptance criteria from the spec are implemented
- [ ] All tasks in `.agent/tasks/` are `done` (`/task status`)
- [ ] All tests pass (the test command in `AGENTS.md` → Essential Commands, e.g. `bun test` / `pytest` / `go test ./...`)
- [ ] No lint or type errors
- [ ] /qa report: no CRITICAL or MAJOR issues
- [ ] /review report: no Critical issues
- [ ] PR created with complete description
- [ ] Deployed to staging (automatic after merge to main)
- [ ] Smoke-tested on staging
