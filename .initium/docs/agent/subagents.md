# Subagents

Initium uses specialist subagents so the parent stays an orchestrator: it decides
what happens next, the specialist does one phase, and the parent applies the
structured return. Isolation matters most in autonomous mode (`/loop`, `/groom` →
`/loop`, `INITIUM_AGENT_MODE=autonomous`), where one long context otherwise mixes
design, implementation, and review.

Specialist definitions live in `.claude/agents/initium-*.md`. Claude Code loads
them natively. Cursor, OpenCode, and other harnesses spawn their Task / Agent
tool with that file as the system prompt (or the matching custom agent name when
the harness lists it).

---

## When to spawn

Read `autonomy.subagents.enabled`. If the key is absent, treat it as `true`. If it is
`false`, run everything inline.

| Situation | Spawn? |
|-----------|--------|
| `/loop` (and `/loop resume`) when a Task / Agent tool exists | **Always** — each phase below |
| `/groom` | No — parent keeps issue-tracker MCP and triage/requirements |
| `/review`, `/security-audit`, `/qa` when a Task / Agent tool exists | **Always** — fresh eyes, even interactively |
| `/architect`, `/implement`, `/debug` | Autonomous: **yes**. Interactive: stay in-session so the developer can steer |
| Nested spawn from a specialist | **Never** — one level only |
| No Task / Agent tool in this session | Run the command inline and say so in one line |

Autonomous means any of: `INITIUM_AGENT_MODE=autonomous`, the command was invoked
from `/loop` or `/groom`, or the session is a headless CLI (`claude -p`,
`cursor --print`, `opencode run`).

---

## Mapping

| Phase / command | Agent `name` | File |
|-----------------|--------------|------|
| `/architect`, `/loop` phase 2 | `initium-architect` | `.claude/agents/initium-architect.md` |
| `/implement`, `/loop` phase 4a (one task) | `initium-implementer` | `.claude/agents/initium-implementer.md` |
| `/review` | `initium-reviewer` | `.claude/agents/initium-reviewer.md` |
| `/qa`, `/loop` phase 5 | `initium-qa` | `.claude/agents/initium-qa.md` |
| `/security-audit`, `/qa` security phase | `initium-security` | `.claude/agents/initium-security.md` |
| `/debug`, `/loop` test-failure retry | `initium-debugger` | `.claude/agents/initium-debugger.md` |

Independent implementation tasks may run as parallel implementers **only** when
`autonomy.subagents.parallel` is `true`, the tasks share no files, and
`max_concurrent_tasks` allows it. Default is sequential, same workspace.

---

## How to spawn

Pass a single packet, not a conversation:

1. Role file path (or paste its body as the subagent system prompt).
2. The slash-command body to follow (e.g. `.claude/commands/architect.md`) and
   `$ARGUMENTS`.
3. Paths the specialist must read: `AGENTS.md`, `agent.config.yaml`, the task
   state file, requirements/design JSON, and the files in scope.
4. Mode: `autonomous` or `interactive`.
5. Output contract: the JSON/markdown path the parent will read next.
6. Hard limits: do not edit `AGENTS.md`, `CLAUDE.md`, `agent.config.yaml`,
   `.initium/guardrails/`, `.githooks/`, or hook configs. Do not force-push,
   skip hooks, or read secret files. Guardrail hooks still run inside the
   subagent.

The parent **does not redo** the specialist's work. It parses the return, writes
task state, enforces gates (`autonomy.gates`), and either continues, retries, or
`/escalate`.

If the spawn fails or the harness has no subagent tool, fall back to inline
execution of the same command file (the impeccable "degraded" pattern): one
line disclosing the substitution, then the full workflow.

---

## Parent vs specialist

| | Parent (`/groom`, `/loop`) | Specialist |
|--|----------------------------|------------|
| Kill switch, concurrent-task cap, escalation | Yes | Halt and return if `.agent/STOP` exists |
| Git branch create / PR / CI watch | Yes | Implementer commits on the current feature branch only |
| Issue tracker MCP | Yes | No |
| Writing application code | No (except applying a debugger/implementer return that came back as a patch) | Implementer and debugger |
| Approving own review | No | Reviewer and security never edit the code they judged |

---

## Harness notes

**Claude Code.** `Task` with `subagent_type` equal to the agent's `name:`
frontmatter. `--dangerously-skip-permissions` does not skip Initium guardrails.

**Cursor.** If a custom agent with that name is listed, use it. Otherwise spawn
`generalPurpose` (or the closest isolated type) and put the agent file at the
top of the prompt. Do not use `bugbot` or `security-review` unless the user
asked for those Cursor products by name — Initium's `initium-security` follows
`/security-audit`.

**OpenCode.** Use the plugin/task equivalent with the same prompt packet.
`.opencode/commands/` mirrors `.claude/commands/`; agent files are not mirrored
because OpenCode loads `.claude/agents/` when present, and the command text
points at those paths.
