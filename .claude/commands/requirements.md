Analyze the provided requirements and produce a complete, actionable specification ready for development.

Read any referenced documents, existing code, or context files before producing output.

---

## Phase 1: Requirements Clarification

Before decomposing, identify and list any ambiguities:
- What is not specified but must be decided before implementation?
- What are the boundary conditions and edge cases not covered?
- What assumptions am I making?

If blockers exist, surface them now. Continue with reasonable assumptions if minor.

---

## Phase 2: User Stories

Write user stories for every distinct user-facing behavior.

Format:
```
US-001: [Title]
As a [user type],
I want to [action]
So that [benefit/outcome]

Acceptance Criteria:
  - Given [context], when [action], then [expected result]
  - Given [context], when [action], then [expected result]
  - [Edge case / error scenario]
```

Cover: happy paths, error cases, permissions, edge cases.

---

## Phase 3: Technical Requirements

### Functional Requirements
List what the system must DO:
- `FR-001`: [Specific, testable requirement]
- `FR-002`: ...

### Non-Functional Requirements
- **Performance**: e.g., API p99 < 200ms under X concurrent users
- **Security**: e.g., requires authentication; authorization rules
- **Scalability**: e.g., must handle N records
- **Reliability**: e.g., retry behavior, error recovery
- **Accessibility**: e.g., WCAG 2.2 AA for UI features

### Out of Scope
Explicitly list what this feature does NOT include.

---

## Phase 4: Architecture Impact

- **New components / services**: What needs to be created?
- **Modified components**: What existing code changes?
- **Data model changes**: New tables, columns, schema migrations needed?
- **API changes**: New or modified endpoints, events, or contracts?
- **Dependencies**: New external services, libraries, or integrations?
- **Breaking changes**: Any backward-compatibility concerns?

---

## Phase 5: Implementation Backlog

Break into atomic, independently-deliverable tasks. Each task = one PR.

```
TASK-001: [Title]
  Type: feat | fix | chore | refactor
  Layer: backend | frontend | infra | full-stack
  Estimate: XS (< 2h) | S (< 4h) | M (< 1d) | L (< 3d) | XL (needs splitting)
  Depends on: TASK-XXX (if any)
  Description: What exactly needs to be built/changed
  Acceptance: How we verify it's done
```

Order tasks by dependency. Flag any that require further design (use `/architect` on those).

---

## Phase 6: Testing Strategy

- **Unit tests**: What business logic needs unit tests?
- **Integration tests**: What API endpoints or service interactions need integration tests?
- **E2E tests**: Which user journeys need end-to-end coverage?
- **Manual testing**: What requires human verification?

---

## Phase 7: Definition of Done

A checklist that marks the entire feature as complete:

- [ ] All user stories have passing automated tests
- [ ] All acceptance criteria verified
- [ ] Code reviewed and approved
- [ ] Security requirements verified (auth, input validation, no secrets in logs)
- [ ] Performance tested under expected load
- [ ] Documentation updated (API docs, AGENTS.md if new patterns, architecture docs if applicable)
- [ ] Deployed to staging and smoke-tested
- [ ] Product owner sign-off (if applicable)

---

Requirements to analyze: $ARGUMENTS
