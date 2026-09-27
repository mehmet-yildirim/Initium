# Autonomous Agent Workflow

This document defines the complete state machine, phase gates, and decision logic
for the autonomous AI development agent. The executable definitions are the slash commands
`/groom` (poll → triage → requirements), `/triage`, `/loop` (architect → deploy for one task),
and `/escalate`; thresholds and limits come from `agent.config.yaml`.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AUTONOMOUS AGENT ORCHESTRATOR                    │
│                                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │  POLLER  │──▶│ TRIAGER  │──▶│ PLANNER  │──▶│  EXECUTOR LOOP   │ │
│  │          │   │          │   │          │   │                  │ │
│  │Pull from │   │Domain    │   │Require-  │   │Architect →       │ │
│  │JIRA/     │   │relevance │   │ments →   │   │Implement →       │ │
│  │Linear/GH │   │check     │   │Sprint    │   │QA → PR → Monitor │ │
│  └──────────┘   └──────────┘   └──────────┘   └──────────────────┘ │
│        │               │              │                  │          │
│        ▼               ▼              ▼                  ▼          │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                    ESCALATION MANAGER                           ││
│  │   Confidence < threshold │ Risk ≥ MEDIUM │ Retry limit exceeded ││
│  │   /escalate → Slack / GitHub issue / Email / PagerDuty          ││
│  └─────────────────────────────────────────────────────────────────┘│
│        │               │              │                  │          │
│        ▼               ▼              ▼                  ▼          │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                    STATE STORE & AUDIT LOG                      ││
│  │   .agent/state/<task-id>.json                                   ││
│  │   .agent/audit/<date>-decisions.jsonl                           ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

## Full State Machine

```
                    [NEW ISSUE DETECTED]
                            │
                            ▼
                    ┌───────────────┐
                    │    TRIAGE     │ ◀── /triage (called by /groom per issue)
                    │ Domain check  │     Reads domain-boundaries.md, scores confidence
                    └───────────────┘
                     │           │
              conf≥0.80       conf<0.30
                 │                │
                 ▼                ▼
           [ACCEPTED]        [REJECTED] ──▶ Comment on ticket + close
                 │
          0.30≤conf<0.80
                 │
                 ▼
          [ESCALATE_TRIAGE] ──▶ Human comments AGENT_RESUME (accept) or AGENT_REJECT
                 │
           (if ACCEPT)
                 │
                 ▼
         ┌───────────────┐
         │  REQUIREMENTS │ ◀── /requirements (called by /groom)
         │  Analysis     │     Produces: user stories, tasks, DoD (JSON+MD)
         └───────────────┘
                 │                 ── /loop <task-id> starts here ──
          conf≥threshold, all tasks ≤ L?
           Yes │    No │
               │       ▼
               │  [ESCALATE_REQUIREMENTS] ──▶ Human clarifies (AGENT_CLARIFY) → retry or skip
               │
               ▼
         ┌───────────────┐
         │   ARCHITECT   │ ◀── /architect command
         │   Design      │     Produces: design doc, risk level (JSON+MD)
         └───────────────┘
                 │
          risk level check
         LOW─────────MEDIUM/HIGH
           │                │
           ▼                ▼
    [GATE: auto]    [ESCALATE_DESIGN] ──▶ Human comments AGENT_APPROVE_DESIGN
           │                │               (MEDIUM: review; HIGH: blocks until approved)
           │         (if approved)
           └────────────────┘
                    │
                    ▼
         ┌───────────────────┐
         │    IMPLEMENT      │ ◀── /implement command (per task, dependency order)
         │    (per task)     │     Task source: .agent/tasks/*.md (/task next) or
         │                   │     the requirements JSON; retry loop (max_retries)
         │                   │     + /docs per new/modified file
         └───────────────────┘
                 │
           tests pass?
          Yes │    No (retry≤N)
              │       │
              │  [FIX_ATTEMPT] ──▶ /debug → fix → re-test
              │       │
              │  No (retry>N)
              │       │
              │  [ESCALATE_IMPL] ──▶ Human fixes → AGENT_RESUME, or AGENT_SKIP_TASK
              │
              ▼
         ┌───────────────────┐
         │   DOCS SYNC       │ ◀── Conditional on requirements architectureImpact flags
         │   (conditional)   │     apiChanges → /doc-api <path>
         │                   │     schemaChanges → /doc-schema migrations
         └───────────────────┘
                 │
          API breaking change?
              │       │
              │  YES → [ESCALATE_API_BREAKING] ──▶ version bump + migration guide reminder
              │
              ▼
         ┌───────────────┐
         │      QA       │ ◀── /qa command → .agent/outputs/<task-id>-qa-report.json
         │  Full gates   │     lint + types + tests + coverage + security + deps
         └───────────────┘
                 │
             All PASS?
          Yes │    No │
              │       ▼
              │  [AUTO_FIX] ──▶ max 2 attempts (security issues escalate CRITICAL at once)
              │       │
              │  [ESCALATE_QA] ──▶ Human reviews QA failures
              │
              ▼
         ┌───────────────┐
         │   CREATE PR   │ ◀── gh pr create with structured metadata
         │               │     Links to issue tracker ticket
         └───────────────┘
                 │
                 ▼
         ┌───────────────┐
         │  MONITOR CI   │ ◀── gh pr checks <pr> --watch
         │               │     Auto-fix lint/format failures, re-watch
         └───────────────┘
                 │
             CI PASS?
          Yes │    No │
              │       ▼
              │  [ESCALATE_CI] ──▶ Human fixes CI issue
              │
              ▼
         ┌───────────────┐
         │  MERGE GATE   │ ◀── git.auto_merge.enabled: false → wait for human merge
         │               │     true → squash-merge once approvals are met
         └───────────────┘
                 │
                 ▼
         ┌───────────────┐
         │    DEPLOY     │ ◀── Staging via CI when staging_auto_deploy: true
         │  Staging auto │     Smoke tests → tracker status "In Review"
         │  Prod → gate  │     Production waits for AGENT_APPROVE_DEPLOY
         └───────────────┘     (/deploy has the full checklist and rollback steps)
                 │
           Deploy OK?
          Yes │    No │
              │       ▼
              │  [ROLLBACK + ESCALATE]
              │
              ▼
         ┌───────────────┐
         │    MONITOR    │ ◀── Watch error rate, p99 latency, new alerts for 30 min
         │  Post-deploy  │
         └───────────────┘
                 │
          Metrics stable?
          Yes │    No │
              │       ▼
              │  [AUTO_ROLLBACK + ESCALATE CRITICAL post_deploy_error_spike]
              │
              ▼
         ┌───────────────┐
         │     DONE      │ ◀── Update issue tracker: status = Done
         │               │     Write audit log entry
         └───────────────┘
```

## Task State Schema

Every task in flight has a state file at `.agent/state/<task-id>.json`
(`observability.state_store.path`). The full JSON Schema is
[`schemas/task-state.json`](schemas/task-state.json):

```json
{
  "taskId": "PROJ-42",
  "title": "Add discount code to checkout",
  "source": { "tracker": "jira", "url": "https://..." },
  "phase": "implement",
  "status": "in_progress",
  "startedAt": "2024-03-09T10:00:00Z",
  "lastUpdatedAt": "2024-03-09T11:30:00Z",
  "timeoutAt": "2024-03-10T10:00:00Z",
  "branchName": "feat/PROJ-42-discount-codes",
  "prUrl": null,
  "prNumber": null,
  "retries": { "implement": 1 },
  "escalations": [],
  "phaseOutputs": {
    "triage":        { "confidence": 0.92, "accepted": true },
    "requirements":  { "outputFile": ".agent/outputs/PROJ-42-requirements.json" },
    "architect":     { "outputFile": ".agent/outputs/PROJ-42-design.json", "risk": "low" },
    "implement":     { "tasksCompleted": 3, "tasksTotal": 5 },
    "qa":            null,
    "deploy":        null
  },
  "auditTrail": [
    { "at": "2024-03-09T10:00:00Z", "action": "triage_accepted",  "note": "conf=0.92" },
    { "at": "2024-03-09T10:05:00Z", "action": "requirements_done","note": "5 tasks identified" },
    { "at": "2024-03-09T10:30:00Z", "action": "design_done",      "note": "risk=low" },
    { "at": "2024-03-09T11:00:00Z", "action": "implement_started", "note": "task 1/5" }
  ]
}
```

## Phase Gate Contracts

Each phase gate checks these conditions before proceeding automatically. Defaults shown come
from `agent.config.yaml`; the escalation severity and trigger names match `/loop` and the
[escalation protocol](escalation-protocol.md).

| Phase Gate | Auto-proceed if... | Escalate if... | Config key |
|-----------|-------------------|----------------|------------|
| After TRIAGE | confidence ≥ 0.80 | 0.30 ≤ conf < 0.80 (MEDIUM); < 0.30 auto-rejects | `domain.acceptance_threshold`, `domain.rejection_threshold` |
| After REQUIREMENTS | confidence ≥ 0.75 AND all tasks sized ≤ L AND no blocking ambiguity | confidence below threshold → MEDIUM `requirements_confidence_low`; XL tasks must be split | `autonomy.gates.requirements.confidence_threshold` |
| After ARCHITECT | risk = low | risk = medium (MEDIUM `design_risk_medium`) or high (HIGH `design_risk_high`, blocks) | `autonomy.gates.architect.risk_threshold`, `autonomy.require_approval_for_risk` |
| After each IMPLEMENT task | all tests pass + /docs run on new files | tests fail after 3 retries (HIGH `implement_max_retries_exceeded`) or task exceeds 8 h | `autonomy.gates.implement.max_retries`, `max_hours` |
| After DOCS SYNC | /doc-api no errors (if apiChanges); /doc-schema updated (if schemaChanges) | API breaking change (MEDIUM `api_breaking_change_detected`) | — |
| After QA | all gates PASS, coverage ≥ 80% | security issue (CRITICAL `security_vulnerability_detected`); other gates still failing after 2 auto-fix attempts (HIGH `qa_gate_failure`) | `autonomy.gates.qa.coverage_threshold` |
| After CI | all checks green | unfixable check failure (HIGH `ci_pipeline_failure`) | — |
| Before PROD DEPLOY | never — always waits for `AGENT_APPROVE_DEPLOY` | LOW notice: "PR merged, staging healthy" | `autonomy.gates.deploy.require_human_approval` |
| After POST-DEPLOY MONITOR | metrics stable for 30 min | error rate / latency degradation (CRITICAL `post_deploy_error_spike`) | — |
| Whole task | finished within 24 h | timeout (HIGH `task_timeout`) | `autonomy.task_timeout_hours` |

## Resume After Interruption

If the agent crashes or is stopped, it resumes from the last checkpoint:

```bash
# Check in-flight tasks
ls .agent/state/

# Resume a specific task
/loop resume PROJ-42
```

`/loop` accepts a task ID or `resume <task-id>`; there is no resume-all mode — resume each
in-flight task from `.agent/state/` individually (within `autonomy.max_concurrent_tasks`).

The agent reads the state file, determines the last completed phase, and continues from there.
It never re-runs completed phases unless explicitly requested (for example with an
`AGENT_RESUME phase=<phase>` comment on the escalation).

## Concurrency Model

By default (`autonomy.max_concurrent_tasks: 1`), the agent works on one task at a time.
When the limit is reached, `/groom` queues accepted issues instead of starting them.
To enable parallel development:

1. Set `autonomy.max_concurrent_tasks: N` in `agent.config.yaml`
2. Each task gets its own git branch (`git.branch_pattern` / `git.branch_patterns_by_type`) and state file
3. Tasks with dependencies wait for their dependencies' PRs to merge first
4. Dependency is inferred from the `dependsOn` field of each task in the requirements output

## Kill Switch

To stop the agent immediately (emergency):
```bash
touch .agent/STOP
```
The agent checks for this file (`safety.kill_switch_file`) before each phase transition and
exits cleanly if found. In autonomous mode (`INITIUM_AGENT_MODE=autonomous`) the guardrail hooks
also deny every command and file write while it exists. Remove the file to re-enable the agent.

The other `safety:` settings — `protected_paths`, `forbidden_file_patterns`,
`forbidden_commands`, and the PR size limits — are enforced by the guardrail hooks and the
pre-commit hook; see [guardrails.md](../guardrails.md).

---

## Containerized Deployment

The agent can run as a long-lived Docker container with a built-in cron scheduler, requiring no developer machine or manual invocation.

```
┌──────────────────────────────────────────────────────┐
│              initium-agent container                 │
│                                                      │
│  /initium/          ← Initium runtime (baked in)     │
│    .claude/         ← slash commands, hooks          │
│    .cursor/         ← rules, MCP config              │
│    .continue/       ← multi-model config             │
│    .opencode/       ← OpenCode slash commands        │
│    opencode.json    ← OpenCode instructions          │
│    agent.config.yaml                                 │
│                                                      │
│  /workspace/        ← your project (cloned at start) │
│    .claude/  ─────────────── overlay if absent ──▶   │
│    .cursor/  ─────────────── overlay if absent ──▶   │
│    .continue/ ────────────── overlay if absent ──▶   │
│    .opencode/ ────────────── overlay if absent ──▶   │
│    src/ ...                                          │
│                                                      │
│  cron: GROOM_CRON → /groom-runner.sh                 │
│    git fetch + rebase → $AGENT_CLI "/groom" → push   │
└──────────────────────────────────────────────────────┘
```

**Tooling overlay rule:** If a directory (`.claude/`, `.cursor/`, `.continue/`, `.opencode/`) or `opencode.json` / `agent.config.yaml` is already present in the cloned repo, it is used as-is. The image copy is only applied when absent. This means projects initialized with `/init` use their own customized copies automatically.

**Scheduling:** The `GROOM_CRON` environment variable controls the schedule (standard cron syntax). It defaults to `*/15 * * * *`, matching `agent.config.yaml → issue_tracker.<provider>.poll_interval_minutes: 15`.

**Kill switch in container:** Create `.agent/STOP` in the workspace — the runner script checks for it before each `/groom` invocation without requiring a container restart.

See [docker-agent.md](docker-agent.md) for the full setup guide, all environment variables, and troubleshooting steps.
