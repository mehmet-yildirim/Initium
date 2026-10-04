Execute the full autonomous development loop for a single task.
Takes a task from requirements output through architecture, implementation, QA, PR creation,
CI monitoring, and post-deploy verification.

This command is the core executor. /groom calls it per accepted issue.
It can also be invoked directly for a known task ID.

---

## Safety Pre-checks

Before doing anything:
1. Check for kill switch: if `.agent/STOP` exists → halt and report
2. Load `agent.config.yaml` and verify all required config is present
3. Check current task count against `max_concurrent_tasks`
4. Read the task state file if it exists (for resume after interruption)

If resuming: skip completed phases, continue from last checkpoint.

---

## Subagent dispatch

`/loop` is an orchestrator. When `autonomy.subagents.enabled` is true (default)
and this session exposes a Task / Agent / subagent tool, **do not** execute
architect, implement, QA, review, security, or debug in this context. Spawn the
matching specialist from `.claude/agents/` with the packet defined in
[subagents.md](../../.initium/docs/agent/subagents.md). Apply the structured
return, update task state, then continue or `/escalate`.

| Phase | Spawn |
|-------|--------|
| 2 Architect | `initium-architect` |
| 4a each task | `initium-implementer` (sequential unless `subagents.parallel` and no shared files) |
| 4b test failure | `initium-debugger` |
| 5 QA | `initium-qa` |
| 5b / before PR | `initium-reviewer` then `initium-security` with scope `diff` |

If no subagent tool exists, run the slash-command bodies inline and say so once.

Never spawn nested specialists. Never spawn work that edits guardrail or policy
files. Honor `.agent/STOP` between phases.

---

## Phase 1: Validate Requirements Input

Load `.agent/outputs/<task-id>-requirements.json`.
Verify:
- All tasks are sized ≤ L (XL tasks must be split before proceeding)
- No blocking ambiguities unresolved
- confidence ≥ requirements threshold from agent.config.yaml

If confidence < threshold → `/escalate medium requirements_confidence_low <task-id>`

---

## Phase 2: Architecture Design

Spawn `initium-architect` (or run `/architect` inline if no subagent tool):

```
/architect <task-title>

Requirements: [paste requirements JSON tasks and user stories]

Architecture constraints from AGENTS.md:
[paste relevant architecture section]
```

Parse the design output for:
- `risk` level (low / medium / high)
- List of files to create and modify
- New dependencies (any new packages?)

**Risk gate:**
- `low` → proceed automatically
- `medium` → `/escalate medium design_risk_medium <task-id>` → wait for `AGENT_APPROVE_DESIGN`
- `high` → `/escalate high design_risk_high <task-id>` → BLOCK until approved

Save design to `.agent/outputs/<task-id>-design.json`.
Update task state: phase = `architect`, status = `completed`.

---

## Phase 3: Create Branch

```bash
git checkout main && git pull origin main
git checkout -b <branch-name-from-config-pattern>
```

Branch name pattern from `agent.config.yaml` → `git.branch_pattern`.
Update task state: `branchName = <branch>`.

---

## Phase 4: Implement (Task Loop)

**Determine task source:**
1. If `.agent/tasks/` directory exists and contains `*.md` files → use task files as source
   - Run `/task next` to get the next `todo` task respecting dependencies
   - After each successful implementation + commit → run `/task done <TASK-ID>`
2. Otherwise → parse tasks from `.agent/outputs/<task-id>-requirements.json`

For each task (in dependency order):

```
TASK: <task-id> — <task-title>
Layer: <layer> | Estimate: <estimate>
```

### 4a. Implement the task

Spawn `initium-implementer` for this task only (or run `/implement` inline):

```
/implement <task-id>: <task-title>

Layer: <layer>
Design context: [paste relevant design section for this task]
Files to change: [from design output]
```

### 4b. Run tests immediately
```bash
<test command from AGENTS.md>
```

### 4c. Check result

**If tests pass:**

Generate documentation for new or significantly changed files in this task:
```
/docs <new-or-modified-source-file>
```
Commit code + updated doc comments together:
```bash
git add <changed files>
git commit -m "<type>(<scope>): <task title>"
```
Update task state: `implement.tasksCompleted++`

**If tests fail (retry loop):**
```
Attempt N of <max_retries from agent.config.yaml>:
Spawn `initium-debugger` with the failing test output (or `/debug` inline).
[Apply the returned fix if the specialist reported `blocked`]
[Re-run tests]
```

If still failing after max_retries:
```
/escalate high implement_max_retries_exceeded <task-id>
  failingTest: <test name>
  errorMessage: <error>
  attemptsLog: [<attempt summaries>]
  hypothesis: <agent's best guess at root cause>
```
→ PAUSE and wait for `AGENT_RESUME` or `AGENT_SKIP_TASK`

**Safety check before each commit:**
- Scan staged files against `safety.forbidden_file_patterns`
- Verify no files in `safety.protected_paths` are modified
- If violation found → abort commit and escalate

---

## Phase 4.5: Documentation Sync (Conditional)

After all implementation tasks are committed, check the requirements JSON for these flags
from `.agent/outputs/<task-id>-requirements.json`:

### If `architectureImpact.apiChanges: true` — update OpenAPI spec
```
/doc-api <service or path touched by this task>
```
Pass the service or directory that contains the changed controllers/handlers
(`git diff --name-only main...HEAD` lists them). This scans them, updates `openapi.json`, validates the spec,
and generates a fresh ReDoc output. If new endpoints are undocumented, generates stubs.

Commit the updated spec:
```bash
git add openapi.json openapi-bundled.json docs/api/ 2>/dev/null
git commit -m "docs(api): update OpenAPI spec for <task-title>"
```

If `/doc-api` reports **breaking changes** (removed endpoints, changed schemas):
```
/escalate medium api_breaking_change_detected <task-id>
  changes: [list of breaking changes]
  action: ensure version bump and migration guide before PR merge
```

### If `architectureImpact.schemaChanges: true` — update DB schema docs
```
/doc-schema migrations
```
This reads the migration files committed in the previous phase and regenerates:
- Mermaid ERD embedded in `docs/architecture/`
- Table reference in `docs/database/schema.md`

Commit if docs changed:
```bash
git add docs/database/ docs/architecture/erd.md 2>/dev/null
git commit -m "docs(schema): update ERD and table reference for <task-title>" 2>/dev/null || true
```

### If neither flag is set — skip this phase
No documentation sync needed for this task.

Update task state: phase = `docs_sync`, status = `completed`.

---

## Phase 5: Quality Assurance

After all implementation tasks and documentation sync are committed:

Spawn `initium-qa` (or run `/qa` inline). Then spawn `initium-reviewer` and
`initium-security` with scope `diff` before opening a PR. A `block` / `fail`
verdict is a QA gate failure.

```
/qa
```

Parse the structured QA report from `.agent/outputs/<task-id>-qa-report.json`.

**If `overallPass: true`** → proceed to PR creation.

**If `overallPass: false`:**
- For each blocking issue, attempt auto-fix (max 2 attempts):
  - Lint errors → run `<format command>` and commit fix
  - Type errors → fix and commit
  - Test failures → spawn `initium-debugger` (subject to max_retries)
  - Security issues → `/escalate critical security_vulnerability_detected <task-id>`
  - Coverage below threshold → generate missing tests with `/test <uncovered-file>`

If QA cannot be resolved after auto-fix:
```
/escalate high qa_gate_failure <task-id>
```

---

## Phase 6: Create Pull Request

```bash
gh pr create \
  --title "<conventional-commit-title>" \
  --body "$(generate-pr-body)" \
  --label "ai-generated" \
  --assignee "@me"
```

PR body must include:
- Link to the issue tracker ticket: `Closes <tracker-url>`
- Summary of changes (from implementation output)
- How to test manually
- QA report summary (link to `.agent/outputs/<task-id>-qa-report.json`)
- Risk level from design phase
- Checklist (auto-populated from PULL_REQUEST_TEMPLATE.md)

Update task state: phase = `pr`, `prUrl = <url>`, `prNumber = <N>`.

---

## Phase 7: Monitor CI

Poll GitHub Actions for the PR's CI status every 2 minutes.

```bash
gh pr checks <pr-number> --watch
```

**If all checks pass** → proceed to merge gate.

**If any check fails:**
- Attempt to diagnose from CI logs
- If fixable (lint, formatter): auto-fix, push, re-watch
- If not fixable: `/escalate high ci_pipeline_failure <task-id>`

---

## Phase 8: Merge Gate

Check `agent.config.yaml` → `git.auto_merge`:
- `enabled: false` → post comment "CI passed. Ready for review." → wait for human merge
- `enabled: true` → verify approval count and merge:
  ```bash
  gh pr merge <pr-number> --squash --delete-branch
  ```

---

## Phase 9: Post-Merge Deploy

After merge:
1. If `staging_auto_deploy: true` — wait for staging CI to complete
2. Run smoke tests on staging URL
3. If smoke tests pass → update issue tracker: status = "In Review"
4. If `require_human_approval: true` for production → escalate LOW with "PR merged, staging healthy, awaiting production approval"

---

## Phase 10: Post-Deploy Monitoring

After production deploy:

Monitor for 30 minutes:
- Check error rate vs. baseline (from observability config)
- Check p99 latency vs. baseline
- Check for new alerts firing

**If metrics stable:** mark task DONE
- Update issue tracker: status = Done
- Close the escalation if one was open
- Write final audit entry
- Update task state: `phase = done, status = completed`

**If metrics degrade:**
```
/escalate critical post_deploy_error_spike <task-id>
  metric: <error_rate | latency>
  current: <value>
  baseline: <value>
```
Trigger auto-rollback:
```bash
<rollback command from deploy runbook>
```

---

## Final Output

```
╔══════════════════════════════════════════════════════╗
║  TASK COMPLETE: <task-id> — <title>                 ║
╠══════════════════════════════════════════════════════╣
║  Total time:  Xh Ym                                  ║
║  Phases:      triage ✓ → reqs ✓ → design ✓ →          ║
║               implement ✓ → docs-sync ✓ → qa ✓ →     ║
║               security ✓ → pr ✓ → deploy ✓           ║
║  PR:          <pr-url>                               ║
║  Cost:        $X.XX (XYYY tokens)                   ║
║  Escalations: N (all resolved)                       ║
╚══════════════════════════════════════════════════════╝
```

---

Task to execute (task-id or "resume <task-id>"): $ARGUMENTS
