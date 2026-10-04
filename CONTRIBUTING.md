# Contributing to Initium

This guide is for contributors who want to improve **Initium itself** — the rules, skills, prompts, scripts, and documentation that ship with this template. If you are customizing Initium for your own project, see the [README](README.md) and [docs/guides/ai-workflow.md](docs/guides/ai-workflow.md) instead.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions are
accepted under the project's [MIT License](LICENSE).

## Who This Is For

- Adding or improving skill files (language, framework, DevOps)
- Updating rules, prompts, or slash commands
- Improving documentation, scripts, or CI configuration
- Fixing bugs or gaps in Initium

## Repo Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/mehmet-yildirim/Initium.git
   cd Initium
   ```

2. Run the setup script for your platform:
   - **macOS / Linux**: `./.initium/scripts/setup.sh`
   - **Windows PowerShell**: `./.initium/scripts/setup.ps1`
   - **Windows (no PowerShell execution policy)**: `.initium\scripts\setup.cmd`

3. Run the init wizard if you want to test the full flow:
   - **macOS / Linux**: `./.initium/scripts/init.sh`
   - **Windows PowerShell**: `./.initium/scripts/init.ps1`
   - **Windows Batch**: `.initium\scripts\init.cmd`

## What Can Be Contributed

| Area | Location | Notes |
|------|----------|------|
| Skills | `.claude/skills/<name>/SKILL.md` | Single source; Continue rules are generated (see below) |
| Base rules | `.cursor/rules/*.mdc`, `.continue/rules/*.md` | Keep Cursor and Continue in sync |
| Prompts / Commands | `.cursor/prompts/`, `.claude/commands/` | Slash commands; `.opencode/commands/` is generated |
| Docs | `docs/` | Architecture, workflows, agent, context |
| Scripts | `scripts/` | setup, init, validate-ai-config (sh, ps1, bat) |
| CI / GitHub | `.github/` | Workflows, PR template, issue templates |

## Skill Format (Critical)

Skills follow the [Agent Skills](https://agentskills.io) open format and live in exactly one
place: `.claude/skills/<name>/SKILL.md`. Claude Code, Cursor, and OpenCode read that folder
natively; do not duplicate skills into `.agents/skills/` or `.cursor/rules/`.

Frontmatter rules (enforced by `.initium/scripts/sync-skills.mjs`):
- `name` — lowercase letters, digits, single hyphens; max 64 characters; equals the folder name
- `description` — 1–1024 characters; states what the skill covers and when to use it
- `paths` — optional list of globs for file-scoped activation

Generated files — never edit by hand:
- `.continue/rules/skills/<name>.md` ← `node .initium/scripts/sync-skills.mjs`
- `.opencode/commands/<name>.md` ← `bash .initium/scripts/sync-opencode-commands.sh`

## How to Add a New Skill

1. Create `.claude/skills/<name>/SKILL.md` (or run `/skill new <topic>`)
2. Run `node .initium/scripts/sync-skills.mjs` to validate and generate the Continue rule
3. Add `# - .continue/rules/skills/<name>.md` to `.continue/config.yaml` in the correct section
4. Add the skill to `skeleton_owned` in `.initium/initium.json` (both the `SKILL.md` and the Continue rule)
5. Run `.initium/scripts/validate.sh` (or `.ps1` / `.cmd`) — all checks must pass
6. Update `skills/README.md` and `README.md` if the skill table needs a new row

## Naming Conventions

- **Skills**: `lang-<language>`, `fe-<framework>`, `be-<topic>`, `mobile-<platform>`, `devops-<topic>`, `db-<topic>`, `ai-<topic>`, `security-<topic>`, `docs-<topic>`
- **Branches**: `feat/`, `fix/`, `docs/`, `chore/` prefix (see [.cursor/rules/04-git-workflow.mdc](.cursor/rules/04-git-workflow.mdc))
- **Commits**: Conventional Commits format — `feat: add X`, `fix: correct Y`, `docs: update Z`

## PR Guidelines

- Use the checklist in [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md)
- Ensure `validate-ai-config.sh` / `.ps1` / `.cmd` passes before opening a PR
- Keep PRs focused — one concern per PR
- Aim for &lt; 400 lines changed when possible

## Validate Before Submitting

Run the validation script for your platform:

```bash
# macOS / Linux
./.initium/scripts/validate.sh

# Windows PowerShell
./.initium/scripts/validate.ps1

# Windows Batch
.initium\scripts\validate.cmd
```

Expected output: `PASS` for all checks. Fix any `FAIL` before opening a PR.

## Releasing Initium

1. Merge to `main`.
2. Annotated tag `vX.Y.Z` and push it. `.github/workflows/release-image.yml` builds
   `ghcr.io/mehmet-yildirim/initium-agent`, attests and signs the digest, opens (or
   updates) the GitHub Release, and attaches `compose.yaml` plus `agent.env.example`.
3. After the first run, set the GHCR package visibility to Public.
