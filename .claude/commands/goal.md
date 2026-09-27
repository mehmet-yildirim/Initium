Pursue a single primary goal until it is fully complete. Do not stop after partial progress,
a single sub-task, or a “good enough” milestone unless the goal’s Definition of Done is met
or a mandatory escalation gate blocks you.

This command is for end-to-end, uninterrupted execution: plan → implement → verify → finish.

Primary goal: $ARGUMENTS

---

## Execution mode (mandatory)

You are in **goal pursuit mode**:

1. **Do not ask** “should I continue?” or “want me to proceed?” — continue automatically.
2. **Do not end** the session while acceptance criteria remain unmet.
3. **Do not defer** remaining work to the user unless an escalation gate applies (below).
4. After each major step, **immediately** start the next step in the same turn/session until done or blocked.
5. Prefer invoking Initium workflows explicitly: `/requirements`, `/architect`, `/task plan`,
   `/implement`, `/test`, `/qa`, `/review`, `/doc-*`, `/deploy` as the goal requires.

If the user invoked this from OpenCode, treat `/command` references as the corresponding
`.opencode/commands/<name>.md` workflow (same content as `.claude/commands/`).

---

## Safety pre-checks

Before any work:

1. If `.agent/STOP` exists → halt immediately and report (kill switch).
2. Read `AGENTS.md`, `agent.config.yaml` (if present), and `.cursor/rules/04-git-workflow.mdc`.
3. Create a feature branch before writing code (never commit directly to `main` / `develop`).
4. Respect `safety.protected_paths` and `safety.forbidden_file_patterns` from `agent.config.yaml`.

---

## Goal state (checkpointing)

Create or update `.agent/goals/<goal-slug>.json`:

```json
{
  "goalId": "<slug>",
  "title": "<one-line goal>",
  "status": "in_progress",
  "startedAt": "<ISO8601>",
  "lastUpdatedAt": "<ISO8601>",
  "definitionOfDone": ["<criterion 1>", "<criterion 2>"],
  "milestones": [
    { "id": "m1", "title": "...", "status": "pending|in_progress|done|blocked" }
  ],
  "currentMilestone": "m1",
  "blockers": [],
  "auditTrail": []
}
```

Slug: lowercase kebab-case from the goal title (max 48 chars).

On resume (`/goal resume <slug>`): read this file, skip completed milestones, continue from
`currentMilestone`.

---

## Phase 1 — Clarify and lock Definition of Done

If the goal text is vague:

- Infer reasonable scope from repo context and state assumptions explicitly.
- Produce **3–7 measurable** Definition of Done criteria (tests pass, docs updated, PR ready, etc.).
- Write them into the goal state file before coding.

If the goal is already precise, restate it and derive DoD from it.

---

## Phase 2 — Plan (only as much as needed)

Choose the lightest planning path that still de-risks the goal:

| Goal size | Path |
|-----------|------|
| Small fix / single module | Skip `/requirements`; optional short design note → `/implement` |
| Feature / multi-file | `/requirements` → `/architect` → `/task plan` |
| Bug | `/debug` → `/implement` → `/test` |

Record milestones in the goal state file. **Then execute without pausing for approval**
unless a gate below triggers.

---

## Phase 3 — Execute milestone loop

For each milestone until all are `done`:

1. Set milestone `in_progress` in goal state.
2. Run the appropriate workflow (`/implement`, `/migrate`, `/infra`, etc.).
3. Run project tests (`AGENTS.md` Essential Commands).
4. If tests fail → `/debug` → fix → re-test (up to 3 attempts per milestone).
5. Mark milestone `done`; advance `currentMilestone`; append audit entry.
6. **Immediately** begin the next milestone in the same session.

Documentation: for new or materially changed public APIs, run `/docs` or `/doc-api` as needed.

---

## Phase 4 — Quality gate

When all milestones are done:

```
/qa
```

If QA fails → auto-fix where safe → re-run `/qa`. After 2 full QA cycles still failing →
`/escalate high goal_qa_blocked <goal-slug>` and stop.

Optional but recommended before PR: `/review`, `/security-audit` when the goal touched auth,
payments, or external input.

---

## Phase 5 — Completion criteria

The goal is **complete** only when **all** are true:

- Every item in `definitionOfDone` is satisfied (cite evidence: test output, file paths, PR URL).
- Working tree is clean or only intentional uncommitted files are explained.
- Goal state: `status = "completed"`, all milestones `done`.

Print a final summary:

```
╔══════════════════════════════════════════════════════╗
║  GOAL COMPLETE: <title>                              ║
╠══════════════════════════════════════════════════════╣
║  Branch:     <branch>                                 ║
║  DoD:        <N>/<N> criteria met                     ║
║  Milestones: <N>/<N> done                             ║
║  Next:       <open PR / deploy / human step if any>   ║
╚══════════════════════════════════════════════════════╝
```

If a PR is part of DoD, create it with `gh pr create` per project template unless the user
forbade PR creation in the goal text.

---

## Escalation gates (only reasons to stop)

Stop autonomous pursuit **only** when:

| Condition | Action |
|-----------|--------|
| `.agent/STOP` present | Halt |
| Design risk `high` from `/architect` | `/escalate` — wait for human |
| Security critical from `/security-audit` or `/qa` | `/escalate critical` |
| Missing secret, credential, or external approval | `/escalate` — document blocker in goal state |
| Same milestone failed tests after 3 debug cycles | `/escalate high goal_implement_blocked` |

Otherwise: **keep going** until Phase 5 completion.

---

## Anti-patterns (do not do)

- Stopping after “I’ve implemented the core part” while DoD items remain.
- Listing “next steps for the user” instead of performing them when tools allow.
- Skipping tests or QA to finish faster.
- Force-push, skip hooks, or bypass CI.
