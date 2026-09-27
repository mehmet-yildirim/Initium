# Cursor Slash Commands

Cursor reads slash commands directly from `.claude/commands/` — no separate Cursor prompt files are needed. All commands (`/implement`, `/debug`, `/qa`, `/goal`, etc.) are defined once and work in Claude Code and Cursor.

[OpenCode](https://opencode.ai/) uses the same prompts from [`.opencode/commands/`](../../.opencode/commands/), kept in sync via:

```bash
bash .initium/scripts/sync-opencode-commands.sh
```

## How to use

Type `/` in Cursor Chat or Composer to see the full command list, or invoke directly:

```
/goal      Ship discount codes end-to-end — do not stop until DoD is met
/implement Add JWT authentication to the login endpoint
/debug     NullPointerException in OrderService.checkout()
/qa        Run full quality cycle before opening PR
```

## Available commands

See [`.claude/commands/`](../../.claude/commands/) for the full list. All commands available in Claude Code are equally available in Cursor and OpenCode.

## Context loading

Cursor loads project context through `.cursor/rules/` (always-on and on-demand rules). OpenCode reads `AGENTS.md` natively and adds the same rules via `opencode.json` → `instructions`. Commands reference `AGENTS.md` for project conventions — ensure it is filled in before running any command.
