Assess whether the provided JIRA/Linear/GitHub issue belongs to this project's domain.
Produce a structured triage decision that the autonomous agent uses to accept or reject the issue.

---

## Step 1: Load Domain Context

Read these files before making any assessment:
1. `docs/context/domain-boundaries.md` — the authoritative scope definition
2. `docs/context/project-brief.md` — project purpose and user types
3. `agent.config.yaml` → `domain` section — threshold settings

Check the `Last reviewed` date in domain-boundaries.md. If older than 30 days, include a
`WARN: domain-boundaries.md may be stale` note in the output.

---

## Step 2: Extract Issue Signal

From the provided issue, extract:
- **Title**: what is being requested?
- **Description**: key entities, actions, and systems mentioned
- **Type**: Story / Bug / Task / Spike
- **Labels / Components**: any explicit area tags
- **Acceptance criteria** (if present)

Identify all domain-relevant signals:
- Entities mentioned (e.g., Order, Payment, Cart, User)
- Actions (e.g., "refund", "checkout", "sync inventory")
- Systems referenced (e.g., "Stripe", "warehouse", "analytics dashboard")
- Ownership clues (e.g., "the frontend team", "our API", "the shipping service")

---

## Step 3: Domain Relevance Assessment

Score against each dimension:

### 3a. Entity Match
Do the entities in the issue appear in the domain's "Entities That Belong to This Domain" list?
- All entities match: +0.3
- Some entities match: +0.15
- No entities match: 0

### 3b. Functional Area Match
Does the requested work fall within the listed in-scope functional areas?
- Clear match: +0.4
- Partial match: +0.2
- No match: 0

### 3c. System Ownership
Does implementing this require changes to THIS repository's code?
- Yes, clearly our code: +0.2
- Unclear / could be another service: +0.05
- No, touches only external/other systems: 0

### 3d. Hard Exclusion Check
Does the issue mention any out-of-scope systems or keywords from the exclusion list?
- Hard exclude keyword found: final confidence = 0.1 (immediate low signal)
- Boundary case found: reduce score by 0.2

**Total confidence** = sum of dimensions (capped at 1.0)

---

## Step 4: Decision

Based on thresholds in `agent.config.yaml`:

| Confidence | Decision |
|-----------|----------|
| ≥ acceptance_threshold (default 0.80) | ACCEPT — agent proceeds autonomously |
| ≥ rejection_threshold (default 0.30) and < acceptance_threshold | ESCALATE — human triage needed |
| < rejection_threshold (default 0.30) | REJECT — out of domain |

---

## Step 5: Output

Produce both a **human-readable summary** and a **machine-readable JSON block**.

### Human Summary
```
TRIAGE RESULT: [ACCEPT | ESCALATE | REJECT]
Confidence: X.XX

Reasoning:
- [Key signal 1 that influenced the decision]
- [Key signal 2]
- [Any hard exclusion signals or uncertainty factors]

[If ESCALATE]: Specific question for human: "..."
[If REJECT]: Suggested destination: "This appears to belong to [team/system].
  Suggested action: reassign to [team] or close as won't-do."
```

### Machine-Readable JSON
```json
{
  "taskId": "<issue-id>",
  "phase": "triage",
  "action": "<triage_accepted | triage_escalated | triage_rejected>",
  "timestamp": "<ISO-8601>",
  "confidence": 0.00,
  "decision": "<ACCEPT | ESCALATE | REJECT>",
  "reasoning": "<one paragraph>",
  "signals": {
    "entityMatches": ["<entity1>", "<entity2>"],
    "functionalAreaMatches": ["<area1>"],
    "systemOwnership": "<our_code | unclear | external>",
    "hardExclusionFound": false,
    "hardExclusionKeyword": null
  },
  "escalationQuestion": null,
  "suggestedDestination": null,
  "domainBoundariesVersion": "<last-reviewed-date>"
}
```

---

## Step 6: Post-Triage Actions

**If ACCEPT:**
- Update issue tracker status to "In Progress" (via MCP or gh CLI)
- Add label: `ai-agent-accepted`
- Create state file: `.agent/state/<task-id>.json`
- Proceed to `/requirements`

**If REJECT:**
- Add comment to the issue: "This issue is outside this project's domain. [Reasoning].
  Suggested: [redirect]."
- Add label: `ai-agent-rejected`
- Close or transition the issue

**If ESCALATE:**
- Create escalation notification (see `.initium/docs/agent/escalation-protocol.md`)
- Add label: `ai-agent-needs-triage`
- Add comment: "Domain relevance is ambiguous (confidence: X.XX). [Question].
  Please comment AGENT_RESUME to accept or AGENT_REJECT to decline."
- Wait for human response

---

Issue to triage: $ARGUMENTS
