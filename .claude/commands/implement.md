Execute a structured implementation of the specified task or feature.

Follow this workflow strictly. Do not skip phases.

---

## Subagent dispatch

In **autonomous** mode (`INITIUM_AGENT_MODE=autonomous`, or invoked from `/loop` /
`/groom`), if a Task / Agent tool exists, spawn `initium-implementer`
(`.claude/agents/initium-implementer.md`) with this file, `$ARGUMENTS`, and the
packet in [subagents.md](../../.initium/docs/agent/subagents.md). Do not implement
in the parent context. Interactive sessions stay in-process unless the developer
asks to delegate.

---

## Step 0: Branch Check

Verify you are on a feature branch (`feat/`, `fix/`, or `chore/` prefix). If on `main` or `develop`, stop and create one first (see AGENTS.md → Git Workflow).

---

## Step 1: Orient

Before writing any code:
1. Read `AGENTS.md` for project conventions
2. If `codegraph.enabled` is `true` in `agent.config.yaml`, locate the affected symbols with the
   code graph first (`search_graph`, `trace_path`, `get_file_outline`) and read only the files
   you will change. Otherwise read the relevant existing code files (the feature area being changed)
3. Read related tests to understand expected behavior patterns
4. Identify all files that will need to change

State: "I have read [files]. The current implementation does [X]. I will change [Y]."

---

## Step 2: Design (if not already done)

If a design document or `/architect` output is not available for this task, produce a brief design:
- Approach: how will this be implemented?
- Files to create or modify
- Any new types, interfaces, or schemas
- Potential risks or gotchas

Pause here if the design is unclear. Ask for clarification before proceeding.

---

## Step 3: Implement — Bottom Up

Implement in dependency order (innermost layers first):

1. **Types / Schemas / Interfaces** — Define the data shapes first
2. **Domain / Business Logic** — Pure functions and domain rules
3. **Data Access / Repository** — Database queries and mutations
4. **Service / Use Case** — Orchestration of domain + data access
5. **API Handler / Controller** — HTTP/event handling (thin layer)
6. **UI Components** — Frontend (if applicable)

After each file, verify:
- Does it compile / pass type checking?
- Is error handling complete?
- Are there obvious edge cases unhandled?

---

## Step 4: Write Tests Alongside Code

For each implemented unit, write tests immediately (do not defer):
- Unit test for the business logic
- Integration test for the data access layer
- API test for the handler

Test structure: Arrange → Act → Assert
Test naming: `'does X when Y'`

---

## Step 5: Self-Review

Before declaring complete, review your own output:

**Correctness**
- [ ] Does it implement all acceptance criteria?
- [ ] Are all error paths handled?
- [ ] Are edge cases covered?

**Security**
- [ ] No injection vulnerabilities (SQL, command, XSS)
- [ ] Input validated at the boundary
- [ ] Authorization checked before data access
- [ ] No secrets or PII in logs

**Code Quality**
- [ ] Consistent with existing code style
- [ ] No dead code or commented-out code
- [ ] Names are clear and descriptive
- [ ] No magic strings or numbers

**Tests**
- [ ] All tests pass
- [ ] Coverage includes the happy path, error cases, and edge cases
- [ ] Tests are meaningful (would catch a real bug)

---

## Step 6: Update Task Status

If this implementation was for a tracked task in `.agent/tasks/`:

1. **Mark the task done** — update the task file's frontmatter:
   ```
   status: done
   completed: <ISO date>
   ```
2. **Update the task index** — in `.agent/tasks/INDEX.md`, update the task row's Status column to `done` and note any newly unblocked tasks
3. **Report** — print:
   ```
   ✅ TASK-XXX marked done.
   Next unblocked: TASK-YYY — <title>  (or "All tasks complete. Run /qa.")
   ```

Skip this step only if no `.agent/tasks/` directory exists for this feature.

---

## Step 7: Summarize Changes

Produce a concise summary:

```
## Changes Made

### New Files
- `path/to/file.ts` — [one-line description]

### Modified Files
- `path/to/existing.ts` — [what changed and why]

### Tests
- `path/to/file.test.ts` — [what's tested]

### Remaining Work
- [Anything NOT completed and why]
- [Follow-up tasks needed]
```

---

---

Task to implement: $ARGUMENTS
