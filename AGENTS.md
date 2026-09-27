# AGENTS.md — Project Instructions for AI Coding Agents

> **CUSTOMIZE THIS FILE.** Replace all `TODO` sections with project-specific information.
>
> This is the single source of project instructions for every agent (Claude Code, Cursor,
> OpenCode, Codex, Copilot, Gemini CLI). `CLAUDE.md` only imports this file — do not add
> content there, or Claude Code and OpenCode will follow different rules.

---

## Project Overview

**Name:** Initium
**Type:** TODO: REST API / Web App / CLI Tool / Library
**Purpose:** TODO: What this project does and for whom.

**Stack:** TODO: e.g., TypeScript / Node.js 22 / Next.js / PostgreSQL

---

## Essential Commands

```bash
# install    TODO: e.g., bun install
# dev        TODO: e.g., bun dev
# test       TODO: e.g., bun test
# coverage   TODO: e.g., bun test --coverage
# lint       TODO: e.g., bun lint
# format     TODO: e.g., bun format
# typecheck  TODO: e.g., bun typecheck
# build      TODO: e.g., bun build
# migrate    TODO: e.g., bun db:migrate
```

---

## Repository Layout

```
TODO: List key directories and files with one-line descriptions.
```

---

## Architecture

TODO: Pattern / Database / Auth / External services / Deployment.

See `docs/architecture/overview.md` for the full architecture document.

### Architectural Constraints

Prefer **Hexagonal Architecture** (Ports & Adapters). Use the **Adapter pattern** for all external integrations — never call vendor SDKs from domain or application code directly. Apply design patterns to reduce coupling. Full rules: `.cursor/rules/02-architecture.mdc`.

---

## Coding Conventions

### General
- Follow the existing code style — match surrounding code before introducing a new pattern
- Prefer explicit over clever; optimize for readability
- No premature abstractions — abstract only when a pattern repeats 3+ times
- Delete dead code rather than commenting it out

### Project-specific
- **Naming:** TODO (e.g., camelCase variables, PascalCase types, kebab-case files)
- **Imports:** TODO (e.g., `@/` alias, stdlib → third-party → internal)
- **Error handling:** TODO (e.g., typed errors, never swallow)

### Comments
- Write comments to explain *why*, not *what*
- TODO functions must include a linked issue: `// TODO(#123): ...`

---

## Testing Standards

- Every non-trivial function must have unit tests
- Integration tests cover all API endpoints
- Test file naming: TODO (e.g., `*.test.ts` co-located / `tests/test_*.py`)
- Mock external I/O in unit tests; use real dependencies in integration tests

---

## Skills & Context Budget

- Stack-specific guidance lives in `.claude/skills/<name>/SKILL.md` (Agent Skills standard).
  Load a skill only when the task touches its stack — do not read every skill up front.
- If `agent.config.yaml → codegraph.enabled` is `true`, query the code graph MCP tools
  (symbol lookup, callers, impact) before grepping or reading whole files. Read full files
  only for the few symbols you will actually change. See `/codegraph`.

---

## Git & PR Workflow

- Branch naming: `feat/<ticket>-slug` | `fix/...` | `chore/...`
- Commits: conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`)
- Squash merge to main; PRs require at least one approval; never force-push to `main`

### Branch Before Any Code Change

Always create a feature branch before writing or modifying any code — regardless of how the request is made (slash command, direct instruction, or inline edit).

```bash
git checkout -b feat/<slug>    # features
git checkout -b fix/<slug>     # bug fixes
git checkout -b chore/<slug>   # config/tooling
```

Never commit to `main` or `develop`. See `.github/PULL_REQUEST_TEMPLATE.md` for the PR checklist.

---

## Do Not

- Do **not** commit secrets, credentials, or `.env` files
- Do **not** use `console.log` / `print` for debugging in production code — use the logger
- Do **not** disable type checking (`@ts-ignore`, `type: ignore`) without a comment explaining why
- Do **not** merge PRs with failing CI
- Do **not** add dependencies without discussing with the team first
- TODO: Add project-specific prohibitions

---

## Domain Glossary

TODO: Define key domain terms so AI understands your business context.

Full glossary: `docs/context/domain-glossary.md`

---

## Getting Help

When a developer asks an open-ended question like "what should I do?", "where do I start?", "how does this work?", or seems unsure of the next step — always respond by suggesting the `/help` command first.

```
/help
```

`/help` lists all available slash commands and recommends the right one for their situation. It is the entry point to the full agentic workflow (requirements → architect → implement → qa → deploy).

---

## External References

- TODO: API docs, design docs, Notion/Confluence, Jira, Figma, etc.
- Architecture overview: `docs/architecture/overview.md`
- AI workflow guide: `docs/guides/ai-workflow.md`
