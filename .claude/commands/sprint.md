Plan a development sprint from the provided backlog or theme. Produce a complete sprint plan ready for team execution.

Read any referenced backlog files, project docs, or AGENTS.md context before planning.

---

## Step 1: Sprint Context

Establish:
- **Sprint goal**: One sentence describing what success looks like
- **Duration**: typically 1–2 weeks
- **Team capacity**: available developer-days (account for meetings, reviews, holidays)
- **Carry-over**: any unfinished work from previous sprint?

---

## Step 2: Backlog Analysis

For each candidate backlog item, assess:
- **Value**: what user/business value does it deliver?
- **Dependencies**: does it block or depend on other items?
- **Risk**: unknown technical territory? external dependency?
- **Effort**: XS (< 2h) | S (< 4h) | M (< 1d) | L (< 3d) | XL (must split)

Flag any XL items — they MUST be broken down before entering the sprint.

---

## Step 3: Sprint Backlog Selection

Select items based on priority × capacity. Apply these rules:
- Never commit to more than 70% of theoretical capacity (buffer for reviews, bugs, meetings)
- Include at least one high-value item that can be completed and shipped
- Balance: feature work / tech debt / testing / docs (suggest a ratio for this sprint)
- Leave room for unplanned work (bugs, urgent requests)

---

## Step 4: Task Breakdown

For each selected item, break into atomic tasks (each task = one PR):

```
ITEM: [Title] — [Priority: P0/P1/P2] — [Estimate: S/M/L]
Sprint Goal contribution: [how this advances the goal]

Tasks:
  TASK-001: [Title]
    Estimate: XS | S | M
    Assignee: [role or name]
    Layer: backend | frontend | infra | full-stack
    Depends on: TASK-XXX (if any)
    Description: [what exactly to build/change]
    Definition of Done:
      - [ ] [specific acceptance criterion]
      - [ ] Tests written and passing
      - [ ] Code reviewed and merged
```

---

## Step 5: Sprint Timeline

Map tasks to days, accounting for dependencies:

```
Day 1–2:  [Foundation tasks — unblock others]
Day 3–4:  [Core feature implementation]
Day 5–6:  [Integration, testing, edge cases]
Day 7–8:  [Review buffer, QA, documentation]
Day 9–10: [Sprint review prep, retrospective]
```

Identify the critical path — which task delays risk the sprint goal?

---

## Step 6: Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [External API dependency unavailable] | Medium | High | Use mock/stub; define contract first |
| [Scope creep on Item X] | High | Medium | Timebox to M; defer extras to next sprint |
| [Team member unavailable] | Low | Medium | Cross-train on critical path tasks |

---

## Step 7: Definition of Sprint Done

The sprint is complete when:
- [ ] Sprint goal achieved
- [ ] All committed items: merged to main, deployed to staging, tests passing
- [ ] No HIGH/CRITICAL bugs introduced
- [ ] Documentation updated for any new APIs or significant behavior changes
- [ ] Sprint review demo prepared
- [ ] Retrospective notes captured: what went well, what to improve

---

## Step 8: Sprint Kickoff Checklist

Before sprint starts:
- [ ] All tasks created in the project tracker
- [ ] Dependencies identified and sequenced
- [ ] Ambiguities resolved or escalated
- [ ] Team aligned on sprint goal
- [ ] Environment and tooling ready for all tasks

---

Sprint backlog / theme to plan: $ARGUMENTS
