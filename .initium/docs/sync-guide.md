# Initium Sync Guide

This guide explains how to keep a project that was derived from Initium
in sync as Initium itself evolves — without overwriting your project-specific work.

---

## The Problem

When you clone Initium and start a project, you immediately diverge:

```
Initium repo ──────────────────── v1.0 ──── v1.1 ──── v1.2 ──── v2.0
                    │
                    └──── Your Project (from v1.0)
                              (customised AGENTS.md, docs/context, etc.)
```

Over time Initium gains new slash commands, improved skill rules, security patches,
and new agent capabilities. Your project would benefit from these — but a naive `git pull`
would overwrite everything you've customised.

---

## File Ownership Model

Every file in Initium is classified into one of three categories, defined in `.initium/initium.json`:

### `skeleton_owned` — Safe to overwrite

These files contain **no project-specific content**. Initium owns them completely.
Updates are applied automatically by `sync-initium.sh`.

Examples:
- All `.claude/commands/*.md` — slash command definitions
- All `.claude/skills/*/SKILL.md` — language/framework skills (Agent Skills format)
- All `.continue/rules/skills/*.md` — Continue skill rules (generated from the skills)
- All `.opencode/commands/*.md` — OpenCode command mirrors
- `.initium/docs/agent/` — autonomous agent documentation and schemas
- `.initium/scripts/validate.sh` — configuration validator
- `.agent-templates/` — runtime templates

**You can still extend these in your project** — just know they will be overwritten on sync.
If you have project-specific additions, keep them in a separate file.

### `merge_required` — Review and cherry-pick

These files are a **mix of Initium base content and your customizations**.
The sync script shows you a diff and lets you decide what to adopt.

| File | Why merge is needed |
|------|---------------------|
| `.continue/config.yaml` | You've added API keys and activated skills; Initium adds new skills/commands |
| `.cursor/mcp.json` | You've enabled servers; Initium adds new server entries |
| `.claude/settings.json` | You may have added permissions; Initium adds hook entries |
| `.github/workflows/ci.yml` | Your stack's CI steps; Initium fixes or adds generic steps |
| `docs/guides/ai-workflow.md` | Your project workflow notes; Initium adds new command references |
| `docs/guides/onboarding.md` | Your project-specific setup; Initium adds new sections |
| `.gitignore` | Your project ignores; Initium adds new generated-file patterns |

### `project_owned` — Never overwrite

These files are **entirely yours**. The sync script skips them and only reports
if Initium was updated (so you can read the new guidance):

- `AGENTS.md` — your project's coding conventions and architecture (all agents)
- `CLAUDE.md` — imports `AGENTS.md` for Claude Code; add only Claude-specific notes
- `agent.config.yaml` — your JIRA connection, team settings
- `.cursor/rules/00-project-overview.mdc` — your project context for Cursor
- `docs/context/` — your project brief, tech stack, domain glossary
- `docs/architecture/` — your system architecture and ADRs
- `.env`, `.env.example` — your environment variables
- `.initium/initium.json` — version tracking (updated by sync script only)

---

## How to Sync

### Option 1: Automated script (recommended)

**macOS / Linux / Git Bash (WSL):**
```bash
bash .initium/scripts/sync.sh           # Interactive
bash .initium/scripts/sync.sh --auto    # Auto-apply skeleton-owned files
bash .initium/scripts/sync.sh --dry-run # Preview only
bash .initium/scripts/sync.sh --check   # Check for updates
```

**Windows — PowerShell (recommended on Windows):**
```powershell
# One-time: allow script execution if not already set
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.\.initium\scripts\sync.ps1            # Interactive
.\.initium\scripts\sync.ps1 -Auto     # Auto-apply
.\.initium\scripts\sync.ps1 -DryRun   # Preview only
.\.initium\scripts\sync.ps1 -Check    # Check for updates
```

> **PowerShell advantage on Windows:** No `jq` required — uses built-in
> `ConvertFrom-Json`. For merge-required files, opens VS Code diff (if
> available) instead of vimdiff. Fully equivalent to the bash version.

**Windows — CMD (no bash or WSL required):**
```bat
.initium\scripts\sync.cmd
.initium\scripts\sync.cmd --auto
.initium\scripts\sync.cmd --dry-run
.initium\scripts\sync.cmd --check
```

> `sync-initium.cmd` delegates to `sync-initium.ps1` via `pwsh` or
> `powershell.exe`, both of which are built into Windows. No bash, WSL,
> or `jq` required.

### Option 2: Claude Code command

```
/sync-initium
/sync-initium --auto
/sync-initium --dry-run
```

### Option 3: Manual (when you need full control)

```bash
# 1. Add Initium as a remote (first time only)
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git

# 2. Fetch latest
git fetch skeleton

# 3. Apply a specific file from Initium
git show skeleton/main:.claude/commands/loop.md > .claude/commands/loop.md

# 4. Apply an entire directory of skeleton-owned files
for file in $(git show skeleton/main --name-only --format="" | grep "^\.claude/skills/"); do
  mkdir -p "$(dirname "$file")"
  git show "skeleton/main:$file" > "$file"
done

# 5. Review a merge-required file
git diff skeleton/main:.continue/config.yaml .continue/config.yaml

# 6. Update .initium/initium.json manually
# Edit skeleton.commit and skeleton.syncedAt fields
```

---

## When to Sync

| Trigger | Frequency | Priority |
|---------|-----------|----------|
| Initium releases a new version | Within one sprint of release | High |
| New skill added (language/framework your team uses) | When you start using that tech | Medium |
| Security patch in skill rules | Within a week | High |
| New slash command added | As convenient | Low |
| Check for updates | Every sprint | — |

Subscribe to the Initium repository to get notified of new releases:
`GitHub → Watch → Custom → Releases`

---

## Merge Guide for Each merge_required File

### `.continue/config.yaml`

Initium adds new skill sections. Your version has API keys and activated skills.

**What to take from Initium:**
```yaml
# Look for new section blocks like:
# --- Documentation skills ---
# - .continue/rules/skills/docs-generation.md

# --- Security SAST ---
# - .continue/rules/skills/security-sast.md
```

**What to keep from your version:**
- Your `models:` section with API keys
- Any skills you've uncommented (activated)
- Any custom slash commands you've added

**Merge command:**
```bash
# Open side-by-side
vimdiff .continue/config.yaml <(git show skeleton/main:.continue/config.yaml)  # 'skeleton' is the git remote name
```

### `.cursor/mcp.json`

Initium adds new MCP server entries (always disabled by default).

**What to take from Initium:**
- New server entries like `jira`, `linear`, `slack`, `sentry`
- Updated configurations for existing servers

**What to keep:**
- Any servers you've enabled (removed `"disabled": true` from)
- Your environment variable references

### `.github/workflows/ci.yml`

Initium improves the generic CI template. Your version has stack-specific steps.

**What to take from Initium:**
- New generic job patterns
- Fixed concurrency or caching configurations

**What to keep:**
- Your language-specific build, test, and deploy steps
- Your environment secrets and service configurations

---

## Tracking Which Initium Version You're On

After each sync, `.initium/initium.json` is updated:

```json
{
  "skeleton": {
    "repository": "https://github.com/mehmet-yildirim/Initium",
    "version": "1.2.0",
    "commit": "abc1234def567",
    "syncedAt": "2024-06-15"
  }
}
```

Commit `.initium/initium.json` after every sync so your team can see when the project was last
updated and from which Initium version.

---

## Handling Conflicts

### When Initium changes a file your team also changed

This can happen with `merge_required` files. Resolution order:

1. **Use Initium version** if your changes are minor or Initium's improvement is significant
2. **Keep your version** if the file is heavily customised and the Initium change is minor
3. **Cherry-pick** specific lines using a diff tool if both have valuable changes

### When a skeleton_owned file was customised locally

If you added content to a `skeleton_owned` file (e.g., added a project-specific section
to a skill rule), the sync will overwrite it. Solutions:

**Option A — Create a separate override file**
```
.claude/skills/lang-java/SKILL.md          ← skeleton-owned (will be synced)
.claude/skills/project-java/SKILL.md       ← project-owned (your additions)
```

**Option B — Move to merge_required**
Edit `.initium/initium.json` → `fileOwnership.merge_required` to add your file.
The sync script will then prompt before overwriting.

### When an Initium file is removed

The sync script warns you: "REMOVED in skeleton: `<file>`"
Review whether to also remove it from your project (usually yes).

---

## Keeping Your Own Initium Fork

If your organization maintains a private fork of Initium with company-wide defaults:

1. Fork the Initium repo into your org
2. Apply your company-wide customizations to the fork
3. In each project, set `skeleton.repository` to your fork URL
4. The sync script will pull from your fork, not the public Initium

This lets you add company standards (internal tools, compliance rules, house style)
to Initium while still pulling upstream improvements via your fork.

---

## FAQ

**Q: Will sync break my running application?**
No. The sync only touches AI configuration files (`.claude/`, `.cursor/`, `.continue/`,
`docs/`, `scripts/`). It never modifies your application source code, tests, or data.

**Q: What if I've modified a skeleton_owned file?**
Your modification will be overwritten. Either move your additions to a separate file,
or reclassify the file as `merge_required` in `.initium/initium.json`.

**Q: Can I sync a specific file only?**
Yes: `git show skeleton/main:.claude/commands/loop.md > .claude/commands/loop.md`

**Q: How do I roll back a bad sync?**
`git diff HEAD` shows what changed. `git checkout HEAD -- <files>` restores any file.
Or `git stash` before sync to have a quick escape hatch.

**Q: What if the Initium validator count increases after sync?**
New files were added to Initium. The updated validator checks for them.
Run `bash .initium/scripts/validate.sh` — any FAILs indicate missing new files.
The sync should have applied them; if not, apply manually.
