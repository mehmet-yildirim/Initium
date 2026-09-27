# Escalation Protocol

Defines when the autonomous agent escalates to a human, what information it provides,
and what actions are available to the human responder.

Escalations are raised with `/escalate <severity> <trigger> <task-id> [context]`. The command
writes `.agent/escalations/<escalation-id>.json`, notifies the channels configured in
`agent.config.yaml → escalation`, always opens a GitHub issue for tracking, comments on the
original ticket, sets the task state to `awaiting_human`, and polls for a response.

---

## Escalation Severity Levels

| Level | Meaning | Response Time | Channels (`escalation.severity_routing`) |
|-------|---------|--------------|---------|
| **CRITICAL** | Production broken, data at risk, security issue | Immediate | Slack @here + PagerDuty |
| **HIGH** | Task blocked, repeated failures, risky change | < 2 hours | Slack + GitHub issue |
| **MEDIUM** | Ambiguous requirement, design question, confidence gap | < 8 hours | GitHub issue |
| **LOW** | Informational, soft blocker, FYI | Next working day | GitHub issue |

Severities are passed to `/escalate` in lowercase (`critical`, `high`, `medium`, `low`).

---

## Escalation Triggers

### CRITICAL Escalations

| Trigger | Description |
|---------|-------------|
| `post_deploy_error_spike` | Error rate or p99 latency degraded vs. baseline during the 30-minute post-deploy watch |
| `post_deploy_data_corruption` | Data integrity check failed after deploy |
| `security_vulnerability_detected` | `/qa` or `/security-audit` found a security issue (CVE, injection, exposed secret) in new code |
| `destructive_operation_attempted` | Agent tried to run a command in `safety.forbidden_commands` (DROP TABLE, rm -rf) |
| `budget_exceeded` | Daily/monthly cost budget in `observability.cost_tracking` exceeded |

### HIGH Escalations

| Trigger | Description |
|---------|-------------|
| `implement_max_retries_exceeded` | Failing tests not fixed after `autonomy.gates.implement.max_retries` attempts |
| `task_timeout` | Task exceeded `autonomy.gates.implement.max_hours` or `autonomy.task_timeout_hours` |
| `qa_gate_failure` | `/qa` gates still failing after the auto-fix attempts |
| `ci_pipeline_failure` | CI failed after PR creation and auto-fix attempts failed |
| `design_risk_high` | /architect classified change as HIGH risk — blocks until approved |
| `consecutive_failures` | `safety.consecutive_failure_limit` consecutive failures; agent may be in a bad state |

### MEDIUM Escalations

| Trigger | Description |
|---------|-------------|
| `triage_confidence_ambiguous` | Domain confidence between rejection and acceptance thresholds |
| `requirements_confidence_low` | Requirement too ambiguous to produce reliable user stories |
| `design_risk_medium` | /architect classified change as MEDIUM risk; review requested |
| `out_of_scope_dependency` | Implementing this task requires changing an out-of-scope system |
| `api_breaking_change_detected` | `/doc-api` (docs sync) or `/review` found a backward-incompatible API or schema change |

### LOW Escalations

| Trigger | Description |
|---------|-------------|
| `triage_rejected` | Issue determined to be out of domain (informational) |
| `pr_awaiting_review` | PR created, waiting for human code review |
| `production_approval_requested` | PR merged and staging healthy; production waits for `AGENT_APPROVE_DEPLOY` |
| `task_completed` | Task completed successfully (daily digest) |
| `stale_domain_boundaries` | `domain-boundaries.md` not updated in > 30 days |

---

## Escalation Message Format

Every escalation record (`.agent/escalations/<escalation-id>.json`) and notification follows
this structured format:

```json
{
  "id": "esc-PROJ-42-001",
  "severity": "high",
  "trigger": "implement_max_retries_exceeded",
  "taskId": "PROJ-42",
  "taskTitle": "Add discount code to checkout",
  "taskUrl": "https://jira.company.com/browse/PROJ-42",
  "phase": "implement",
  "summary": "Failed to fix failing test UserService.applyDiscount after 3 attempts.",
  "context": {
    "failingTest": "src/checkout/checkout.service.test.ts:87",
    "errorMessage": "TypeError: Cannot read properties of undefined (reading 'code')",
    "attemptsLog": [
      "Attempt 1: Added null check — still fails",
      "Attempt 2: Changed data fetch order — still fails",
      "Attempt 3: Refactored discount lookup — still fails"
    ],
    "hypothesis": "The test fixture may be missing required discount data. Possible test setup issue.",
    "branchName": "feat/PROJ-42-discount-codes",
    "prUrl": null
  },
  "availableActions": [
    { "action": "approve_and_continue", "description": "Fix the test manually and comment AGENT_RESUME on the task" },
    { "action": "reassign",             "description": "Comment AGENT_REASSIGN to hand the ticket to a human developer" },
    { "action": "skip_task",            "description": "Comment AGENT_SKIP_TASK to skip this sub-task and continue" },
    { "action": "abandon",              "description": "Comment AGENT_ABANDON to stop work on this ticket entirely" }
  ],
  "escalatedAt": "2024-03-09T14:35:00Z",
  "agentId": "my-project-agent",
  "status": "open",
  "resolvedAt": null,
  "resolution": null
}
```

Never include secrets, credentials, or PII in the escalation record or notifications.

---

## Human Response Actions

Humans respond to escalations by posting comments on the GitHub escalation issue or the
original tracker ticket. `/escalate` polls the GitHub issue every 5 minutes; the Jira webhook
receiver (see [docker-agent.md](docker-agent.md)) reacts to ticket comments immediately.

| Comment Command | Effect |
|----------------|--------|
| `AGENT_RESUME` | Agent retakes the task from current phase |
| `AGENT_RESUME phase=architect` | Agent restarts from a specific phase |
| `AGENT_SKIP_TASK` | Skip current sub-task, continue to next |
| `AGENT_REASSIGN` | Remove task from agent queue; hand to human |
| `AGENT_ABANDON` | Stop all work on this ticket; close the agent branch |
| `AGENT_APPROVE_DESIGN` | Approve the design phase output; proceed to implement |
| `AGENT_APPROVE_DEPLOY` | Approve production deployment |
| `AGENT_REJECT` | Reject and close the issue as out of scope (triage escalations) |
| `AGENT_CLARIFY: <text>` | Provide clarification; agent incorporates it and retries |

When a response arrives the agent marks the escalation resolved in the task state, writes an
audit entry, and executes the action.

---

## Escalation Runbook by Trigger

### `implement_max_retries_exceeded`

1. Read the agent's hypothesis in the escalation message
2. Check the failing test: `git checkout <branch> && <test command>`
3. Determine if it's a test setup issue or a real logic bug
4. Either:
   - Fix the test fixture and comment `AGENT_RESUME`
   - Provide a clarification hint and comment `AGENT_CLARIFY: <hint>`
   - Assign to a human developer: `AGENT_REASSIGN`

### `design_risk_high`

1. Read the design document linked in the escalation (`.agent/outputs/<task-id>-design.json`)
2. Review the risk assessment: what specifically is high-risk?
3. Either:
   - Approve with conditions: `AGENT_APPROVE_DESIGN` + `AGENT_CLARIFY: <constraints>`
   - Modify the scope to reduce risk and `AGENT_CLARIFY: <new scope>`
   - Reject as too risky for autonomous implementation: `AGENT_REASSIGN`

### `security_vulnerability_detected` (CRITICAL)

1. Read the findings in the QA report or `.agent/audit/<date>-security-report.json`
2. Revoke and rotate any exposed credential immediately
3. Fix the finding (or confirm a false positive and add a suppression — see
   [security-evaluator.md](security-evaluator.md)), then comment `AGENT_RESUME`

### `post_deploy_error_spike` (CRITICAL)

1. **Immediately**: Check the monitoring dashboard
2. **If user impact confirmed**: Trigger rollback manually
   ```bash
   kubectl rollout undo deployment/app  # or equivalent
   ```
3. The agent will automatically attempt rollback — verify it succeeded
4. Create a post-incident issue in the tracker
5. Investigate root cause before re-enabling the agent for this type of change

### `triage_confidence_ambiguous`

1. Read the triage report in the GitHub issue
2. Review the original tracker ticket
3. Decide: is this in our domain?
4. Comment `AGENT_RESUME` (agent will accept) or `AGENT_REJECT` (agent will decline)

---

## Escalation SLA

The agent will re-escalate (escalation reminder) to the same channels if not responded to within:

| Severity | First reminder | Second reminder | Auto-action after second reminder |
|----------|---------------|----------------|-------------|
| CRITICAL | 15 minutes | 30 minutes | Page on-call rotation |
| HIGH | 2 hours | 4 hours | Assign to team lead |
| MEDIUM | 8 hours | 24 hours | Auto-close escalation, task stays queued |
| LOW | 48 hours | 72 hours | Auto-close escalation, task stays queued |
