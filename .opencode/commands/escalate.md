Raise an escalation when the agent cannot proceed autonomously.
This command packages the escalation context and sends notifications via configured channels.
It also pauses the current task and waits for human response.

Usage: /escalate <severity> <trigger> <task-id>

---

## Step 1: Load Escalation Config

Read `agent.config.yaml` → `escalation` section:
- Primary channel and credentials
- Severity routing (which channels get which severities)
- SLA timers

Read `.initium/docs/agent/escalation-protocol.md` for the canonical trigger definitions and available actions.

---

## Step 2: Build Escalation Context

Gather all relevant context for the human responder:

```
taskId:        <from args>
trigger:       <from args>
severity:      <from args>
phase:         <current workflow phase>
title:         <task title from state file>
issueUrl:      <tracker URL from state file>
branchName:    <git branch if exists>
prUrl:         <PR URL if exists>
summary:       <1-2 sentence description of what went wrong>
context:       <detailed technical context>
  - What was attempted
  - What failed (exact error messages, stack traces)
  - What was tried to fix it (retry attempts)
  - Agent's best hypothesis for root cause
availableActions: <list from escalation-protocol.md matching this trigger>
```

**Do NOT include secrets, credentials, or PII in the escalation message.**

---

## Step 3: Write Escalation Record

Create `.agent/escalations/<escalation-id>.json`:

```json
{
  "id": "esc-<task-id>-<sequence>",
  "severity": "<severity>",
  "trigger": "<trigger>",
  "taskId": "<task-id>",
  "taskTitle": "<title>",
  "taskUrl": "<tracker-url>",
  "phase": "<phase>",
  "summary": "<summary>",
  "context": { ... },
  "availableActions": [ ... ],
  "escalatedAt": "<ISO-8601>",
  "agentId": "<from config>",
  "status": "open",
  "resolvedAt": null,
  "resolution": null
}
```

---

## Step 4: Send Notifications

Based on severity routing in `agent.config.yaml`:

### Slack (if configured)
```
POST ${SLACK_WEBHOOK_URL}
{
  "channel": "#dev-agent-alerts",
  "text": "*[<SEVERITY>] Agent Escalation: <trigger>*\n
    Task: <taskId> — <title>\n
    Phase: <phase>\n
    Summary: <summary>\n
    <@here> Action required. Reply on GitHub issue: <github-escalation-url>"
}
```

### GitHub Issue (always create for tracking)
```bash
gh issue create \
  --title "[Agent Escalation] <severity>: <trigger> on <task-id>" \
  --body "<escalation message with context and available actions>" \
  --label "agent-escalation,<severity>" \
  --assignee "<from config>"
```

Record the GitHub issue URL in the escalation record.

### Comment on Original Ticket (JIRA / Linear / GitHub)
Post a comment on the original issue explaining:
- What the agent attempted
- Why it's escalating
- What the human needs to do (available actions with exact comment commands)

---

## Step 5: Update Task State

```json
{
  "status": "awaiting_human",
  "escalations": [
    {
      "id": "<escalation-id>",
      "trigger": "<trigger>",
      "severity": "<severity>",
      "at": "<ISO-8601>",
      "resolved": false
    }
  ]
}
```

---

## Step 6: Poll for Human Response

Poll the GitHub issue comments every 5 minutes for a response command:

| Comment | Agent action |
|---------|-------------|
| `AGENT_RESUME` | Resume from current phase |
| `AGENT_RESUME phase=<phase>` | Resume from specified phase |
| `AGENT_SKIP_TASK` | Skip current sub-task |
| `AGENT_REASSIGN` | Remove from agent queue |
| `AGENT_ABANDON` | Stop all work on this ticket |
| `AGENT_APPROVE_DESIGN` | Approve design and proceed |
| `AGENT_APPROVE_DEPLOY` | Approve production deploy |
| `AGENT_CLARIFY: <text>` | Provide clarification, retry |

When a response is detected:
1. Mark escalation as resolved in the state file
2. Log resolution to audit trail
3. Execute the appropriate action

---

## Step 7: SLA Re-escalation

If no response within the SLA window (from escalation-protocol.md):
- Send a reminder notification to the same channels
- If second reminder also unanswered:
  - CRITICAL/HIGH → escalate to next tier (PagerDuty, team lead)
  - MEDIUM/LOW → auto-close escalation, keep task queued

---

## Output

```
ESCALATION RAISED
═══════════════════════════════════════════════
ID:        esc-<task-id>-001
Severity:  <SEVERITY>
Trigger:   <trigger>
Task:      <task-id> — <title>
Phase:     <phase>
GitHub:    <issue-url>
Slack:     <sent | not configured>

Waiting for human response...
Commands: AGENT_RESUME | AGENT_SKIP_TASK | AGENT_REASSIGN | AGENT_ABANDON
═══════════════════════════════════════════════
```

---

Escalation parameters: $ARGUMENTS
(Format: <severity> <trigger> <task-id> [additional context])
