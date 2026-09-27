# Decision Log Template

Every significant agent decision is recorded as a JSONL entry in `.agent/audit/<date>-decisions.jsonl`
(`agent.config.yaml → observability.audit_log.path`). This file provides the schema and examples for
the audit trail; the authoritative JSON Schema is [`schemas/decision.json`](schemas/decision.json).
Jira webhook deliveries are logged separately to `.agent/audit/<date>-webhooks.jsonl`.

The audit log serves as:
- **Accountability**: what did the agent do and why?
- **Debugging**: replay events to diagnose agent misbehavior
- **Compliance**: evidence of human oversight for regulated environments
- **Learning**: patterns of failures → improvements to agent config

---

## JSONL Entry Schema

Each line in the audit log is a valid JSON object. Required fields: `id`, `taskId`, `phase`,
`action`, `timestamp`, `confidence` (use `null` when not applicable), `reasoning`.

```json
{
  "id": "dec-<taskId>-<sequence>",
  "taskId": "PROJ-42",
  "agentId": "my-project-agent",
  "timestamp": "ISO-8601",
  "phase": "triage | requirements | architect | implement | docs_sync | qa | pr | ci | deploy | monitor",
  "action": "<see action types below>",
  "input": { },
  "output": { },
  "confidence": 0.0,
  "reasoning": "Human-readable explanation of why this decision was made",
  "risk": "low | medium | high | null",
  "alternatives": [ { "description": "...", "rejectionReason": "..." } ],
  "escalated": false,
  "humanOverride": false,
  "reversible": true,
  "durationMs": 1234,
  "tokensUsed": 1500,
  "costUsd": 0.012
}
```

The `id` must match `^dec-[A-Z]+-[0-9]+-[0-9]+$` — for task `PROJ-42` that is `dec-PROJ-42-001`.

---

## Action Types by Phase

### Triage
| Action | Description |
|--------|-------------|
| `triage_started` | Agent began domain relevance check |
| `triage_accepted` | Issue accepted as in-domain |
| `triage_rejected` | Issue rejected as out-of-domain |
| `triage_escalated` | Confidence too low; human triage requested |
| `triage_human_override_accept` | Human overrode rejection → accepted |
| `triage_human_override_reject` | Human overrode acceptance → rejected |

### Requirements
| Action | Description |
|--------|-------------|
| `requirements_started` | Agent began requirements analysis |
| `requirements_completed` | User stories and task backlog produced |
| `requirements_escalated` | Ambiguity too high; human clarification needed |
| `requirements_clarification_received` | Human provided clarification |

### Architect
| Action | Description |
|--------|-------------|
| `design_started` | Agent began design phase |
| `design_completed` | Design document produced |
| `design_risk_assessed` | Risk level determined (low/medium/high) |
| `design_escalated` | High/medium risk; human approval requested |
| `design_approved` | Human approved the design |
| `design_modified` | Human modified design; agent restarted design |

### Implement
| Action | Description |
|--------|-------------|
| `implement_task_started` | Agent started a sub-task |
| `implement_task_completed` | Sub-task code written and tests pass |
| `implement_test_failed` | Tests failed after implementation attempt |
| `implement_fix_attempt` | Agent trying to fix failing tests (attempt N) |
| `implement_escalated` | Max retries exceeded; human help needed |
| `implement_committed` | Code committed to branch |

### QA
| Action | Description |
|--------|-------------|
| `qa_started` | QA cycle started |
| `qa_lint_pass` / `qa_lint_fail` | Lint result |
| `qa_typecheck_pass` / `qa_typecheck_fail` | Type check result |
| `qa_tests_pass` / `qa_tests_fail` | Test suite result |
| `qa_coverage_pass` / `qa_coverage_fail` | Coverage check |
| `qa_security_pass` / `qa_security_fail` | Security audit result |
| `qa_completed_pass` | All QA gates passed |
| `qa_completed_fail` | One or more gates failed |

### Deploy
| Action | Description |
|--------|-------------|
| `pr_created` | Pull request opened |
| `ci_watching` | Agent monitoring CI status |
| `ci_passed` | All CI checks passed |
| `ci_failed` | CI failed after PR creation |
| `staging_deployed` | Deployed to staging |
| `production_approval_requested` | Human approval needed for production |
| `production_deployed` | Deployed to production |
| `rollback_triggered` | Automatic rollback initiated |
| `task_completed` | Entire task lifecycle complete |
| `task_abandoned` | Task abandoned due to unresolvable issue |

---

## Example Audit Log Entries

```jsonl
{"id":"dec-PROJ-42-001","taskId":"PROJ-42","agentId":"my-project-agent","timestamp":"2024-03-09T10:00:00Z","phase":"triage","action":"triage_started","input":{"issueTitle":"Add discount code to checkout","issueType":"Story","priority":"High"},"output":{},"confidence":null,"reasoning":"New issue detected in JIRA polling","escalated":false,"humanOverride":false,"durationMs":0,"tokensUsed":0,"costUsd":0}

{"id":"dec-PROJ-42-002","taskId":"PROJ-42","agentId":"my-project-agent","timestamp":"2024-03-09T10:00:15Z","phase":"triage","action":"triage_accepted","input":{"issueTitle":"Add discount code to checkout"},"output":{"confidence":0.92,"signals":["checkout","discount","order"]},"confidence":0.92,"reasoning":"Issue involves discount codes applied at checkout. Checkout and payment processing are core domain. Keywords 'discount', 'checkout' match strong_include_keywords. No exclusion keywords detected.","escalated":false,"humanOverride":false,"durationMs":15000,"tokensUsed":850,"costUsd":0.007}

{"id":"dec-PROJ-42-007","taskId":"PROJ-42","agentId":"my-project-agent","timestamp":"2024-03-09T11:45:00Z","phase":"implement","action":"implement_test_failed","input":{"task":"TASK-003: Add discount validation service","attempt":1},"output":{"failingTest":"checkout.service.test.ts:87","error":"TypeError: Cannot read properties of undefined"},"confidence":null,"reasoning":"Test fixture missing 'discountCode' field setup. Attempting fix.","escalated":false,"humanOverride":false,"durationMs":45000,"tokensUsed":2100,"costUsd":0.018}
```

---

## Reading the Audit Log

```bash
# View all decisions for a task
grep '"taskId":"PROJ-42"' .agent/audit/2024-03-09-decisions.jsonl | jq .

# Count escalations today
grep '"escalated":true' .agent/audit/$(date +%Y-%m-%d)-decisions.jsonl | wc -l

# Total cost for a task (-h drops file-name prefixes so jq sees pure JSON)
grep -h '"taskId":"PROJ-42"' .agent/audit/*-decisions.jsonl | jq -s 'map(.costUsd // 0) | add'

# View all failed QA runs
grep -h '"action":"qa_completed_fail"' .agent/audit/*-decisions.jsonl | jq '{task: .taskId, time: .timestamp}'
```

---

## Retention

- Audit logs are JSONL files rotated daily
- Retention: 90 days recommended. `agent.config.yaml` has no retention key — enforce it with
  logrotate or your log shipper
- Logs must not be deleted while a related task is still in flight
- For compliance requirements: archive to S3/GCS before local deletion
