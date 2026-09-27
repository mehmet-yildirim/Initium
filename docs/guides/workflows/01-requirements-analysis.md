# Workflow: Requirements Analysis

This workflow transforms raw requirements (feature requests, user stories, bug reports, product specs)
into a structured, implementation-ready specification using AI assistance.

## When to Use This Workflow

- New feature development (any size)
- Significant refactoring with behavior changes
- Ambiguous or complex bug fixes
- Technical spike / proof of concept

Skip for: trivial bug fixes, config changes, documentation-only updates.
For a small, well-defined change you want finished end-to-end in one session, `/goal <objective>`
picks the lightest planning path itself (it skips `/requirements` for single-module fixes).

## The Workflow

```
Input: Raw requirement (ticket, Slack message, doc, verbal description)
  │
  ├─ Step 0: Triage (backlog issues only — /triage or /groom)
  ├─ Step 1: Clarify & Gather Context
  ├─ Step 2: AI-Assisted Analysis (/requirements)
  ├─ Step 3: Human Review & Refinement
  ├─ Step 4: Technical Spike (if unknown territory)
  └─ Output: Approved spec → /architect → /task plan (or /sprint for sprint planning)
```

## Step 0: Triage (backlog issues)

When the input is an issue from the tracker rather than a direct request, first check that it
belongs to this project:

```
/triage <issue key or pasted issue>   # single issue: accept / reject / escalate with a confidence score
/groom                                 # batch: fetch backlog → /triage each → /requirements for accepted ones
```

`/triage` scores the issue against `docs/context/domain-boundaries.md` and
`docs/context/project-brief.md`. `/groom` saves each accepted issue's analysis to
`.agent/outputs/<task-id>-requirements.json`, which `/loop <task-id>` picks up in autonomous mode
(see [Autonomous Workflow](../../../.initium/docs/agent/autonomous-workflow.md)).

## Step 1: Clarify & Gather Context

Before running AI analysis, collect:

**From the requester:**
- Who are the users affected?
- What problem does this solve? (not just what it should do)
- What is the success metric?
- What is the priority / urgency?
- Are there designs, mockups, or reference examples?

**From the codebase:**
- Which existing components are relevant?
- Are there similar features already implemented?
- Are there known constraints (performance, security, backward compat)?

If `codegraph.enabled` is `true` in `agent.config.yaml`, use `/codegraph` (symbol search, callers,
impact) to answer these questions without reading whole files.

## Step 2: AI-Assisted Requirements Analysis

```bash
# In Claude Code, Cursor, OpenCode, or Continue:
/requirements <paste the raw requirement here>
```

The `/requirements` command produces:
- Clarifying questions and assumptions (answer these before proceeding)
- User stories (`US-001`) with Given/When/Then acceptance criteria
- Functional (`FR-001`) and non-functional requirements, plus an explicit "Out of scope" list
- Architecture impact assessment (components, data model, API, dependencies, breaking changes)
- Implementation backlog (`TASK-001`, sized XS–L, XL flagged for splitting, ordered by dependency)
- Testing strategy (unit, integration, E2E, manual)
- Definition of Done

## Step 3: Human Review

Review the AI output critically. Check:

**Correctness**
- Does the specification match the original intent?
- Are business rules captured accurately?
- Are the user stories testable?

**Completeness**
- Are all user types covered?
- Are error cases and edge cases specified?
- Is the "out of scope" section accurate?

**Feasibility**
- Are effort estimates realistic?
- Are any tasks too large (XL)? Split them.
- Are dependencies identified?

**Gaps**
- What did the AI miss or misunderstand?
- Correct the spec and re-run if significantly wrong.

## Step 4: Technical Spike (if needed)

If the implementation approach is uncertain, run a time-boxed spike (max 2 days):

```
/architect <specific unknown aspect>
```

Goal of spike: answer a specific technical question (e.g., "Can we integrate with X API?",
"What's the performance characteristic of approach Y?").
Spike output: a documented decision, NOT production code. `/architect` saves it as
`docs/architecture/decisions/NNNN-<feature>.md` (next free number; see `0001-template.md`).
For performance questions, measure with `/perf` instead of guessing.

## Output: Approved Specification

The approved specification should contain:

```markdown
# Feature: [Name]

## Status: Approved / Draft / Needs Review

## Sprint: [Sprint number or "Backlog"]

## User Stories
[From /requirements output]

## Acceptance Criteria
[From /requirements output]

## Technical Notes
[Architecture decisions, constraints, risks]

## Implementation Tasks
[Ordered task list from /requirements output]

## Definition of Done
[Checklist]
```

Store approved specs in: `docs/features/<feature-name>.md` (create the folder on first use).

## Next Steps

- Design the implementation: `/architect <task or spec>` — see [Feature Development](02-feature-development.md)
- Turn the design into tracked task files: `/task plan`
- New UI surface: add `/design` (after `/design-system` once per project) before implementation
- LLM-powered feature: plan an evaluation suite with `/eval create <feature>` alongside the tests
- Planning a whole sprint instead: `/sprint <backlog or theme>`

## Common Pitfalls

- **"I'll figure it out as I code"** — skipping requirements analysis leads to rework. The `/requirements` command takes 5 minutes; rework takes days.
- **AI takes the requirement too literally** — always review the user story section for missing implied behavior.
- **Scope creep in specs** — the AI may include nice-to-haves. Keep the "Out of scope" section rigorous.
- **Missing non-functional requirements** — performance, security, and accessibility (WCAG 2.2 AA; see the [`accessibility` skill](../../../.claude/skills/accessibility/SKILL.md)) are easy to overlook. Explicitly prompt for them with measurable targets (e.g. p95 latency).

## Time Estimates

- Simple feature: 15–30 minutes for requirements analysis
- Medium feature: 30–60 minutes (including stakeholder clarification)
- Complex feature: 2–4 hours (may include spike)

The time saved in implementation and rework far exceeds this investment.
