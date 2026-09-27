# Initium Updates — Migration Guide

This file documents every breaking and notable change to Initium
so that projects derived from Initium can apply updates selectively.

When Initium is updated, add an entry here **before** tagging a new version.
Derived projects reference this file to decide what to apply.

---

## How to Apply Initium Updates to Your Project

```bash
# One command — handles classification, diff, and selective application
bash .initium/scripts/sync.sh
```

See [.initium/docs/sync-guide.md](.initium/docs/sync-guide.md) for the full guide.

---

## v1.2.0 — Automatic update checks and weekly sync PRs

**Date:** 2026-09-27
**Commit:** (set by release)
**Severity:** MINOR (with manual merge steps)

### Why
- Derived projects only learned about new Initium releases when someone remembered to run
  `sync.sh`. The sync script also needed a human at the keyboard, so it could not run in CI.
- Syncing followed upstream `main`, so half-finished work could reach derived projects.
  Syncs now target release tags by default.

### New Files (skeleton-owned — auto-applied)
- `.github/workflows/initium-sync.yml` — weekly (Monday 06:00 UTC) and manual check; opens a
  `chore/initium-sync-v<version>` PR with Initium-owned updates, a `merge_required` checklist,
  and release notes. Opens a draft PR if validation fails. Never merges anything.
- `.initium/scripts/check-update.mjs` — cached, dependency-free update check (Node 22).
  `--hook` prints a one-line notice for Claude Code sessions and never fails, even offline.

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.{sh,ps1,cmd}`:
  - targets the latest `vX.Y.Z` tag (`channel: tags`), falling back to `main` when no tags exist
  - `--ref <tag|branch>` pins a version; `--channel tags|main` overrides the config
  - `--auto` is fully non-interactive (also when no TTY); refuses to run on a dirty working tree
  - `--check` exits `10` when an update is available; `--json` prints machine-readable status
  - `--summary <file>` (bash) writes a PR body; `$GITHUB_OUTPUT` is set when running in Actions
  - adds new skeleton-owned files and removes files Initium deleted — only if unmodified locally
  - ownership lists are read from the target version, not the local copy
  - PowerShell: files are written byte-exact and `initium.json` formatting is preserved
- `.initium/scripts/validate.sh` — a missing file no longer aborts all remaining checks
- `.initium/scripts/validate.{sh,ps1,cmd}` — check the two new files
- `.claude/commands/sync-initium.md` (+ OpenCode mirror) — reuses an open sync PR branch,
  `--check` → `--dry-run` → apply → semantic merge → migration steps → verify
- `.initium/initium.json` — new `fileOwnership.removed` list
- `.initium/docs/sync-guide.md`, `README.md`, `README.tr.md`

### Merge Required
- `agent.config.yaml` — add the `initium_sync:` section:
  ```yaml
  initium_sync:
    channel: tags            # tags | main
    auto_pr: true            # weekly workflow opens a PR
    notify_local: true       # Claude Code session notice
    check_interval_hours: 24
  ```
- `.claude/settings.json` — add the `SessionStart` hook:
  ```json
  "SessionStart": [
    { "matcher": "startup",
      "hooks": [{ "type": "command", "command": "node .initium/scripts/check-update.mjs --hook", "timeout": 10 }] }
  ]
  ```

### Migration Steps
1. Merge the two files above.
2. GitHub: enable *Settings → Actions → General → Workflow permissions → Allow GitHub Actions
   to create and approve pull requests*.
3. Optional: add an `INITIUM_SYNC_TOKEN` secret (fine-grained PAT with contents + pull requests
   write). PRs opened with the default `GITHUB_TOKEN` do not trigger your CI workflows.
4. Not on GitHub? Schedule `bash .initium/scripts/sync.sh --auto --summary sync.md` in your CI
   and open a merge request from the result.
5. Run `bash .initium/scripts/sync.sh --check` once to confirm the remote is reachable.

---

## v1.1.0 — Agent Skills standard, AGENTS.md, 9 new stacks, 7 new commands

**Date:** 2026-09-27
**Commit:** (set by release)
**Severity:** MINOR (with manual migration steps)

### Why
- `AGENTS.md` is now read natively by Cursor, OpenCode, Codex, Copilot, and Gemini CLI. Keeping
  instructions only in `CLAUDE.md` made OpenCode and Claude Code follow different files.
- The open [Agent Skills](https://agentskills.io) format (`<name>/SKILL.md`) is loaded natively
  by Claude Code, Cursor, and OpenCode with progressive disclosure — only descriptions cost
  context until a skill is needed. `.cursor/rules/skills/*.mdc` worked in Cursor only.
- `.claude/skills/` is the single source because it is the one location all three tools read;
  also copying to `.agents/skills/` would make Cursor and OpenCode load every skill twice.

### New Files (skeleton-owned — auto-applied)
- `.claude/skills/<name>/SKILL.md` — 23 existing skills migrated + 9 new:
  `ai-llm-apps`, `lang-rust`, `lang-kotlin` (backend), `be-node`, `lang-php`,
  `devops-terraform`, `devops-observability`, `be-messaging`, `be-graphql-grpc`
- `.claude/commands/` — `/codegraph`, `/refactor`, `/upgrade`, `/perf`, `/a11y`, `/eval`, `/skill`
  (+ `.opencode/commands/` mirrors)
- `.initium/scripts/sync-skills.mjs` — validates skill frontmatter and generates
  `.continue/rules/skills/*.md` (`--check` for CI)

### Updated Files (skeleton-owned — auto-applied)
- `.continue/rules/skills/*.md` — now generated from `SKILL.md` (full content, not condensed)
- `.claude/commands/*` — reference `AGENTS.md`; `/implement` uses the code graph when enabled;
  `/help` lists the new commands
- `.claude/hooks/post-write.mjs` — `AGENTS.md` is a protected path
- `opencode.json` — drops `CLAUDE.md` and skill rules (read natively); adds disabled `codegraph` MCP
- `.initium/scripts/validate.{sh,ps1,cmd}`, `setup.*`, `init.*` — `AGENTS.md`, skills validation
- `skills/README.md`, `CONTRIBUTING.md`, `.initium/docs/sync-guide.md`, guides

### Removed
- `.cursor/rules/skills/*.mdc` — replaced by `.claude/skills/<name>/SKILL.md`

### Merge Required
- `agent.config.yaml` — new `codegraph:` section (disabled); `AGENTS.md` added to `safety.protected_paths`
- `.cursor/mcp.json` — new disabled `codegraph` server (`npx -y codebase-memory-mcp`)
- `.continue/config.yaml` — commented entries for the new skills
- `.gitignore` — `.codebase-memory/`

### Migration Notes
1. **Move your instructions to `AGENTS.md`** (project-owned, so sync will not do it for you):
   ```bash
   git mv CLAUDE.md AGENTS.md
   printf '@AGENTS.md\n' > CLAUDE.md
   sed -i.bak 's/CLAUDE\.md/AGENTS.md/g' agent.config.yaml && rm agent.config.yaml.bak  # protected_paths
   ```
   Keep Claude Code-only notes (if any) below the import line in `CLAUDE.md`.
2. **Delete the legacy skill rules** after syncing: `git rm -r .cursor/rules/skills/`.
   If you customised any of them, move your additions into a `.claude/skills/project-<topic>/SKILL.md`.
   `validate.sh` warns while the old folder still contains `.mdc` files.
3. Regenerate derived files: `node .initium/scripts/sync-skills.mjs` (requires Node.js 22+).
4. Optional — code graph: run `/codegraph setup`, then set `codegraph.enabled: true`.
5. Claude Code ships bundled `/debug` and `/loop` skills; if a name collides, the project command in
   `.claude/commands/` is the one Initium documents — invoke it explicitly if your client prompts.

---

## v1.0.24 — OpenCode support and /goal command

**Date:** 2026-08-10
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `.claude/commands/goal.md` — `/goal`: pursue one primary objective until Definition of Done without stopping mid-way
- `.opencode/commands/*.md` — full mirror of Initium slash commands for [OpenCode](https://opencode.ai/)
- `.opencode/README.md` — OpenCode usage and sync instructions
- `opencode.json` — project instructions (`CLAUDE.md` + `.cursor/rules/`)
- `.initium/scripts/sync-opencode-commands.sh` — copy `.claude/commands/` → `.opencode/commands/`

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/help.md` — documents `/goal`
- `.initium/docker/groom-runner.sh` — `AGENT_CLI=opencode` dispatches `/groom`
- `.initium/docker/Dockerfile` / `entrypoint.sh` — bake and overlay `.opencode/` + `opencode.json`
- `.initium/scripts/validate.{sh,ps1,cmd}` — OpenCode sync check
- `README.md` / `README.tr.md`, `docs/guides/onboarding.md`, `.cursor/prompts/README.md`

### Migration Notes
- Install OpenCode locally; open the repo — slash commands match Claude/Cursor (`/help` for the list).
- Container agents: set `AGENT_CLI=opencode` only if the `opencode` CLI is installed in the image (not bundled by default).
- After customizing `.claude/commands/*.md`, run `bash .initium/scripts/sync-opencode-commands.sh`.

---

## v1.0.23 — Fix Cursor glob pattern format

**Date:** 2026-03-27
**Commit:** (set by release)
**Severity:** PATCH

### Updated Files (skeleton-owned — auto-applied)
- `.cursor/rules/03-testing.mdc` and all 23 `.cursor/rules/skills/*.mdc` files — Glob patterns
  converted from JSON array format (`["a", "b"]`) to Cursor's required comma-separated format
  (`a,b`). The array format was silently treated as invalid by Cursor, causing skill rules to
  never auto-activate on matching files.

### Migration Notes
If your project has customized any `.cursor/rules/skills/*.mdc` frontmatter, update the `globs`
field format:

```yaml
# before (invalid)
globs: ["**/*.ts", "**/*.tsx"]

# after (correct)
globs: **/*.ts,**/*.tsx
```

---

## v1.0.22 — Containerized agent runtime with Docker Compose

**Date:** 2026-03-26
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)

**Docker runtime** (`.initium/docker/`)
- `Dockerfile` — Agent runtime image: Node 22, Claude Code CLI, Cursor CLI, git, cron.
  Bakes in `.claude/`, `.cursor/`, `.continue/`, `.agent-templates/`, and `agent.config.yaml`.
- `docker-compose.yml` — Two services: `agent` (cron polling) and `webhook` (event-driven,
  falls back to cron if `JIRA_WEBHOOK_SECRET` is not set). Both are self-contained.
- `entrypoint.sh` — Clones/pulls `GIT_REPO_URL`, overlays Initium tooling if absent, starts cron.
- `groom-runner.sh` — Cron payload: `git pull` → dispatches `/groom` via `AGENT_CLI` → `git push`.
  Supports `AGENT_CLI=claude` (slash command) and `AGENT_CLI=cursor` (raw prompt from groom.md).
- `webhook-entrypoint.sh` — Starts Jira Server webhook receiver if `JIRA_WEBHOOK_SECRET` is set;
  falls back to cron polling otherwise.
- `.env.example` — All supported environment variables with documentation.

**Agent docs** (`.initium/docs/agent/`)
- `docker-agent.md` — Full setup guide: quick start, all env vars, webhook architecture,
  polling vs. webhook comparison, operations, and troubleshooting.

### Updated Files (skeleton-owned — auto-applied)
- `.initium/docs/agent/autonomous-workflow.md` — Added "Containerized Deployment" section.
- `.initium/docs/UPDATES.md` — This entry.
- `.initium/initium.json` — Version bump; new docker files added to `skeleton_owned`.
- `.initium/scripts/validate.sh` / `validate.ps1` — Updated agent doc paths.
- `.initium/docs/sync-guide.md` — Updated agent doc path reference.

### Updated Files (project-owned — review manually)
- `README.md` / `README.tr.md` — New "Containerized Agent" section; updated repo tree and
  Further Reading. Apply if your project uses the autonomous agent.

### Migration Notes
**Agent doc paths moved** — `docs/guides/agent/` → `.initium/docs/agent/`

If your project references agent docs directly (e.g., in onboarding guides or team docs),
update the paths:

```bash
# Preview
grep -r "docs/guides/agent/" docs/ .claude/ .cursor/

# Apply
find docs/ .claude/ .cursor/ -type f \
  \( -name "*.md" -o -name "*.mdc" \) \
  -exec sed -i 's|docs/guides/agent/|.initium/docs/agent/|g' {} +
```

---

## v1.0.21 — Add /doc-diagrams command for sequence diagram generation

**Date:** 2026-03-24
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `.claude/commands/doc-diagrams.md` — `/doc-diagrams` command. Reads source code and
  traces execution paths to generate Mermaid `sequenceDiagram` blocks for API call flows
  and business process flows. Accepts a specific endpoint (`POST /orders`), a named flow
  (`checkout`, `auth`), or `all` to auto-discover. Outputs to `docs/diagrams/` with one
  `.md` file per flow and an auto-maintained `docs/diagrams/README.md` index. Optional
  `--plantuml` flag generates `.puml` files alongside Mermaid.

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/help.md` — Added `/doc-diagrams` to the DOCUMENTATION section of the
  command reference and added `sequence diagram, flow diagram, API flow, business flow` to
  the topic-to-command mapping table.

### Updated Files (project-owned — update manually)
- `README.md` — Added `/doc-diagrams` to the Documentation Generation table and repo tree;
  updated command count from 27 to 28.
- `README.tr.md` — Same updates in Turkish.

### Migration
No action needed. Run `bash .initium/scripts/sync.sh` to pull the new command file.
The command is immediately available as `/doc-diagrams` in Claude Code and Cursor.

---

## v1.0.20 — sync-initium.cmd no longer requires bash or WSL

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### What Changed
`sync-initium.cmd` now delegates directly to `sync-initium.ps1` via
`pwsh` (PowerShell 7) or `powershell.exe` (Windows PowerShell 5.1).
Both are built into Windows — no bash, Git Bash, WSL, or `jq` required.

`sync-initium.ps1` already contained the full sync implementation, so
no functionality was removed or added. The `.cmd` file is now just a thin
PowerShell launcher (identical pattern to `setup.cmd`, `init.cmd`, etc.).

Also fixed a first-sync bug in `sync-initium.ps1`: when the stored
commit SHA is not in the local repository (first-ever sync), the file
list is now obtained with `git ls-tree -r --name-only` instead of
`git show --name-only`.

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.cmd` — rewritten to call `sync-initium.ps1` directly
- `.initium/scripts/sync.ps1` — fixed first-sync `git ls-tree` call
- `.initium/docs/sync-guide.md` — updated Windows CMD section

### Migration
No action needed. Run `.initium/scripts/sync.cmd` as before — it now
works on any Windows machine without installing bash or WSL.

---

## v1.0.19 — Rename Windows batch scripts from .bat to .cmd

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### What Changed
All four Windows batch scripts have been renamed from `.bat` to `.cmd`.
`.cmd` is the modern Windows script extension — it runs in CMD.EXE with
the same behaviour as `.bat` but signals more clearly that the file is a
Windows command script rather than a legacy DOS batch file.

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/setup.cmd` (was `setup.bat`)
- `.initium/scripts/init.cmd` (was `init.bat`)
- `.initium/scripts/validate.cmd` (was `validate-ai-config.bat`)
- `.initium/scripts/sync.cmd` (was `sync-initium.bat`)
- `.initium/scripts/validate.ps1` — updated internal path references
- `.initium/scripts/validate.sh` — updated path checks
- `initium.json` — ownership entries updated + version bumped to 1.0.19
- All documentation files updated.

### Migration
If you already have the old `.bat` files in your derived project:
1. Rename them to `.cmd` (or re-run `.initium/scripts/sync.cmd` after
   adding the new files from Initium).
2. Update any scripts or CI steps that invoke the old `.bat` names.

---

## v1.0.18 — Remove jq dependency from sync-initium.sh

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### What Changed
`.initium/scripts/sync.sh` no longer requires `jq`. All JSON parsing is now
done with `grep`, `sed`, and `awk`, which are available in Git Bash for Windows
without any extra tooling.

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.sh` — replaced all four `jq` call-sites with a
  `_json_array` awk helper and `grep`/`sed` one-liners. No behavioural change.
- `initium.json` — version bumped to 1.0.18.

### Migration
No action needed. The script behaviour is identical; `jq` is simply no longer
required. If you had a local workaround that pre-installs `jq` in CI, it can
safely be removed.

---

## v1.0.17 — Compress always-loaded context files

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `CLAUDE.md` — 167 → 124 lines (−43). Compressed Essential Commands to a single compact block, collapsed Architecture bullets, trimmed branch workflow section, merged Coding Conventions sub-items.
- `.cursor/rules/01-coding-standards.mdc` — 103 → 80 lines (−23). Removed language-specific naming TODO, import alias TODO, concurrency TODO, and the TypeScript/Python template sections (these belong in `lang-typescript.mdc` / `lang-python.mdc` skill files, not in an always-loaded rule).
- `.cursor/rules/00-project-overview.mdc` — 47 → 41 lines (−6). Compressed Key Constraints and Domain Glossary TODO sections.

### Net savings
**−72 lines from always-loaded context** (loaded on every Claude Code turn and every Cursor session).

---

## v1.0.16 — Remove .cursor/prompts/ — Cursor reads slash commands from .claude/commands/ directly

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### Removed Files (skeleton-owned — auto-removed on sync)
All 22 files under `.cursor/prompts/` (excluding `README.md`) have been deleted. Cursor reads slash commands directly from `.claude/commands/`, making the prompt files redundant duplicates. **~2,900 lines of duplicated content eliminated.**

### Updated Files (merge-required — review before applying)
- `.cursor/prompts/README.md` — Rewritten to explain that Cursor uses `.claude/commands/` directly.
- `README.md` — Updated Cursor row in the tool table; updated `/help` tip.
- `README.tr.md` — Same in Turkish.
- `docs/onboarding.md` — Updated Cursor setup step 4; updated `/help` references.
- `docs/onboarding.tr.md` — Same in Turkish.

### Migration notes
- **Derived projects:** Delete all files in `.cursor/prompts/` except `README.md`. No functionality is lost — `/implement`, `/debug`, `/qa`, etc. continue to work in Cursor via `.claude/commands/`.
- If you have customized any `.cursor/prompts/*.md` files, migrate those customizations to the corresponding `.claude/commands/*.md` file instead.

---

## v1.0.15 — Reduce token usage across CLAUDE.md and command files

**Date:** 2026-03-23
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `CLAUDE.md` — Removed redundant architecture constraints block (now a 3-line summary referencing `.cursor/rules/02-architecture.mdc`). Compressed verbose TODO placeholder examples. Removed empty glossary table row. **216 → 167 lines; saves ~49 tokens on every conversation turn.**
- `.claude/commands/implement.md` — Compressed 14-line branch check block to 2 lines (CLAUDE.md already carries the full rule in context).
- `.claude/commands/debug.md` — Same branch check compression.
- `.cursor/prompts/implement.md` — Same branch check compression (rule is in `04-git-workflow.mdc`).
- `.cursor/prompts/debug.md` — Same branch check compression.

### Migration notes
- **Derived projects:** Apply `CLAUDE.md` changes carefully — your filled-in project-specific content must be preserved. The architecture constraints block can be removed; replace it with the 3-line summary pointing to `.cursor/rules/02-architecture.mdc`.
- **No behavioral change** — all rules still apply; they are now stored in one canonical location instead of being repeated in every file.

---

## v1.0.14 — Add Turkish translation of team formation guide

**Date:** 2026-03-15
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `docs/team.tr.md` — Full Turkish translation of the team formation guide covering all roles, decision authority matrix, team size recommendations, and anti-patterns.

### Updated Files (merge-required — review before applying)
- `docs/onboarding.md` — Added `docs/team.tr.md` cross-reference.
- `docs/onboarding.tr.md` — Updated team.md reference to point to Turkish version.
- `README.md` — Added `docs/team.tr.md` to Further Reading.
- `README.tr.md` — Same in Turkish.

---

## v1.0.13 — Add team formation guide for AI-native development

**Date:** 2026-03-15
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `docs/team.md` — Comprehensive team formation guide covering: roles (Tech Lead, Domain Owner, Developer, AI Workflow Coordinator, Security Champion), decision authority matrix, team size recommendations (1–3 / 3–6 / 7–15 people), new member onboarding steps, and common anti-patterns.

### Updated Files (merge-required — review before applying)
- `docs/onboarding.md` — Added `docs/team.md` to the "Understanding the Project" reading list.
- `docs/onboarding.tr.md` — Same addition in Turkish.
- `README.md` — Added `docs/team.md` to Further Reading.
- `README.tr.md` — Same in Turkish.

---

## v1.0.12 — Add hexagonal architecture preference and design pattern guidance

**Date:** 2026-03-15
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (project-owned — review and merge manually)
- `CLAUDE.md` — Added "Architectural Constraints" subsection to the Architecture section: hexagonal preference, adapter pattern requirement for external integrations, and a design pattern reference table.

### Updated Files (skeleton-owned — auto-applied)
- `.cursor/rules/02-architecture.mdc` — Added "Standing Rules" block at the top (before the existing project-specific section): hexagonal default, adapter pattern for all external integrations, and design pattern reference table.
- `.continue/rules/02-architecture.md` — Same standing rules added.

---

## v1.0.11 — Enforce branch-before-change rule across all entry points

**Date:** 2026-03-15
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (project-owned — review and apply manually)
- `CLAUDE.md` — Added "Branch Before Any Code Change" subsection to "Git & PR Workflow". Rule explicitly covers slash commands, direct chat instructions, and inline edit requests — not just structured commands.

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/debug.md` — Added Step 0: Branch Check before diagnosis begins, matching the pattern already in `/implement`.
- `.cursor/prompts/debug.md` — Same Step 0 added for Cursor.
- `.cursor/rules/04-git-workflow.mdc` — Added "Branch Before Any Code Change" section at the top of the rule file so it loads as a standing constraint in every Cursor session.

---

## v1.0.10 — Add Turkish onboarding documentation

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `docs/onboarding.tr.md` — Full Turkish translation of `docs/onboarding.md`. Covers prerequisites, initial setup (macOS/Linux/Windows), understanding the project, all 27 AI commands with Turkish descriptions, development workflow, autonomous agent setup, security checklist, and getting help with `/help`.

### Updated Files (merge-required — review before applying)
- `docs/onboarding.md` — Turkish cross-reference updated to point to new `onboarding.tr.md`.
- `README.md` — Added `docs/onboarding.tr.md` to Further Reading table.
- `README.tr.md` — Added `docs/onboarding.tr.md` to Further Reading table with both language labels.

---

## v1.0.9 — Surface /help in README, onboarding, and agent redirect behavior

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (merge-required — review before applying)
- `README.md` — Added "Help & Navigation" section to Slash Commands Reference, `/help` tip after Quick Start, updated command count to 27, added `help.md` to repo tree.
- `docs/onboarding.md` — Added `/help` as first entry in Claude Code commands list, added prominent "Getting Help" block with examples, added tip callout at top of "Setting Up AI Tools".

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/help.md` — Added redirect guidance: when a developer asks a general "what should I do?" question outside of `/help`, the agent responds by directing them to run `/help` instead of answering inline.
- `.cursor/prompts/help.md` — Same redirect guidance for Cursor.

---

## v1.0.8 — Add /help command for developer guidance

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### New Files (skeleton-owned — auto-applied)
- `.claude/commands/help.md` — `/help` command for Claude Code. When invoked with no arguments it prints the full command reference. When given a question or topic it maps the developer to the right command(s) and workflow stage. Never writes code.
- `.cursor/prompts/help.md` — Cursor equivalent of `/help`. Same logic: full reference, phase guidance, topic mapping, and recovery advice. Never writes code.

---

## v1.0.7 — sync-initium.sh: add missing skeleton-owned files

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.sh` — Added "Adding Missing Skeleton-Owned Files" pass after the normal update loop. For each file in `skeleton_owned`, if it does not exist locally it is fetched and created. This handles new files added to Initium whose content hasn't changed since the last sync commit (so they wouldn't appear in `git diff --name-only`), as well as files accidentally deleted from the derived project.

---

## v1.0.6 — Fix initium.json: add 36 missing file ownership entries

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** PATCH

### Updated Files (skeleton-owned — auto-applied)
- `initium.json` — Added all previously unclassified files to ownership lists:
  - **skeleton_owned**: all `.cursor/prompts/*.md`, Windows scripts (`init/setup/validate-ai-config .ps1/.cmd`), `.agent/tasks/.gitkeep` + `TASK-TEMPLATE.md`, `.devcontainer/devcontainer.json`, `CONTRIBUTING.md`, `.initium/docs/UPDATES.md`, `.initium/docs/sync-guide.md`
  - **project_owned**: `README.tr.md`, `docs/ai-workflow.tr.md`

---

## v1.0.5 — Update task status after implementation

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/implement.md` — Added Step 6: Update Task Status; after implementation the agent marks the task file `done`, updates `INDEX.md` status, and reports the next unblocked task
- `.cursor/prompts/implement.md` — Same task status update step added for Cursor users

---

## v1.0.4 — Branch check as Step 0 in /implement

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/implement.md` — Added Step 0: Branch Check; agent verifies it is on a feature branch and hard-stops if on `main`/`develop` before writing any code
- `.cursor/prompts/implement.md` — Same branch check added for Cursor users

---

## v1.0.3 — Enforce feature branch before implementation

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** MINOR

### Updated Files (skeleton-owned — auto-applied)
- `.claude/commands/task.md` — Added Branch Requirement section: agent must create and switch to `feat/<slug>` branch before any implementation; also shown in `/task next` output
- `.cursor/prompts/task.md` — Same branch requirement added for Cursor users

---

## v1.0.2 — Fix sync-initium.sh sync logic

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** PATCH

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.sh` — Three bugs fixed:
  - `((APPLIED++))` / `((SKIPPED++))` with `set -e` silently exited after first file; replaced with `APPLIED=$((APPLIED + 1))`
  - File ownership was read from local (potentially stale) `initium.json`; now reads from `skeleton/main:initium.json` so newly added files are always included
  - First-sync file list used `git show` (single commit diff) instead of `git ls-tree -r` (full tree)
- `initium.json` — Added missing `skeleton_owned` entries: `/task`, `/sync-initium` commands, `toon.mjs` hook, workflows `06`/`07`, `.initium/scripts/init.sh`

---

## v1.0.1 — Fix sync-initium.sh bash 3.2 compatibility

**Date:** 2026-03-14
**Commit:** (set by release)
**Severity:** PATCH

### Updated Files (skeleton-owned — auto-applied)
- `.initium/scripts/sync.sh` — Replaced `mapfile` (bash 4+ only) with `while read` loops
  so the script runs on macOS default bash (3.2) without `command not found: mapfile`

---

## v1.0.0 — Initial Release

**Date:** 2025
**Commit:** Initial

### What's Included
- 20 Claude Code slash commands (full agentic loop)
- 22 Cursor skill rules + 22 Continue skill rules
- Autonomous agent infrastructure (JIRA, webhooks, escalation)
- Security evaluator (/security-audit + security-sast skill)
- Documentation agent (/doc-api, /doc-site, /doc-changelog, /doc-schema)
- On-premise Jira Server setup guide
- Full CI/CD workflow skeleton

**No migration needed** — this is the first version.

---

## Template for Future Entries

```markdown
## vX.Y.Z — Short Description

**Date:** YYYY-MM-DD
**Commit:** <git-sha>
**Severity:** BREAKING | MINOR | PATCH

### Breaking Changes (require manual action)
- **Changed:** `<file>` — what changed and why it matters
  **Action:** <what the developer must do>

### New Features (opt-in)
- **New file:** `.claude/commands/new-command.md`
  **Action:** Run `bash .initium/scripts/sync.sh` — auto-applied (skeleton_owned)

### Updated Files (skeleton-owned — auto-applied)
- `.cursor/rules/skills/lang-java.mdc` — Updated for Java 22 virtual thread patterns
- `.claude/commands/loop.md` — Added docs-sync phase

### Merge-Required Files (developer must review)
- `.continue/config.yaml` — New skill entries added; merge with your model config
  **How:** Compare Initium version with yours; add new skill lines only

### Removed Files
- `old-file.md` — removed because...
  **Action:** `rm old-file.md` from your project
```

---

*Add new entries at the top (newest first).*
