Design the implementation of this feature before writing any code.

---

## Subagent dispatch

In **autonomous** mode (`INITIUM_AGENT_MODE=autonomous`, or invoked from `/loop` /
`/groom`), if a Task / Agent tool exists, spawn `initium-architect`
(`.claude/agents/initium-architect.md`) with this file and `$ARGUMENTS`. The parent
only writes task state from the returned ADR and design JSON. Interactive
`/architect` stays in-process so the developer can steer.

---

Provide a structured design document with the following sections:

## 1. Understanding
Restate the requirement in your own words to confirm correct interpretation. Flag any ambiguities.

## 2. Approach
High-level implementation strategy. Explain the chosen approach and why it fits the architecture.

## 3. Components Affected
List every existing file, module, class, or API that will need to change. For each, describe what changes and why.

## 4. New Components
List new files, classes, services, or types that need to be created. Include proposed file paths and a one-line description of each.

## 5. Data Model Changes
Any database schema changes, new types, or modified types. Include proposed migrations or schema definitions.

## 6. API Changes
New or modified endpoints, message formats, or public interfaces.

## 7. Edge Cases & Risks
What could go wrong? What edge cases must be handled? What are the failure modes?

## 8. Implementation Checklist
An ordered, actionable checklist of steps ready to execute. Each step should be small enough to be a single commit.

## 9. Open Questions
Ambiguities or decisions that need clarification before or during implementation. Tag with who should answer.

---

## Output

After completing all sections above, save the design document to:

```
docs/architecture/decisions/NNNN-<kebab-case-feature-name>.md
```

Where `NNNN` is the next available number in that directory (check existing files to determine it).

Use this file header:

```markdown
# NNNN — <Feature Name>

**Date:** YYYY-MM-DD
**Status:** Draft
**Deciders:** TODO
```

Then append all sections (1–9) below the header.

Do NOT write implementation code yet. This is a design phase. Ask clarifying questions if the requirement is unclear.

Feature to design: $ARGUMENTS
