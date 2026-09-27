# OpenCode integration

Initium slash commands live in [`.claude/commands/`](../.claude/commands/). The same prompt
files are mirrored here for [OpenCode](https://opencode.ai/) (`/.opencode/commands/`).

## Usage

In the OpenCode TUI, run any Initium command by name, for example:

- `/help` — command reference and workflow guidance
- `/goal <primary objective>` — pursue one goal until Definition of Done is met
- `/requirements`, `/architect`, `/implement`, `/qa`, … — full agentic workflow

OpenCode reads `AGENTS.md` and the skills in `.claude/skills/` natively;
[`opencode.json`](../opencode.json) adds the `.cursor/rules/` base rules as instructions and
declares the optional code graph MCP server (disabled until `/codegraph setup`).

## Keeping commands in sync

After editing `.claude/commands/*.md`, refresh OpenCode copies:

```bash
bash .initium/scripts/sync-opencode-commands.sh
```

CI and `validate.sh` can use `--check` to ensure mirrors are up to date.
