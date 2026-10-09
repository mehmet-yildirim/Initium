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
Updates are applied automatically by `.initium/scripts/sync.sh`.

Examples:
- All `.claude/commands/*.md` — slash command definitions
- All `.claude/skills/*/SKILL.md` — language/framework skills (Agent Skills format)
- All `.continue/rules/skills/*.md` — Continue skill rules (generated from the skills)
- All `.opencode/commands/*.md` — OpenCode command mirrors
- `.initium/docs/agent/` — autonomous agent documentation and schemas
- `.initium/scripts/validate.sh` — configuration validator
- `.agent-templates/` — runtime templates

**You can still extend these in your project** — just know they will be overwritten on sync.
Keep project-specific additions in a separate file, or list the file under your local
`project_owned` (see [Handling Conflicts](#when-a-skeleton_owned-file-was-customised-locally)).

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
- `DESIGN.md`, `PRODUCT.md`, `CHANGELOG.md`, `LICENSE`, `CODE_OF_CONDUCT.md`, `README*`
- `.initium/initium.json` — version tracking (updated by sync script only)

**Your local list wins.** Ownership lists come from the Initium version you sync to, with one
exception: every path under `fileOwnership.project_owned` in *your* `.initium/initium.json` is
never written, even when Initium owns it. The sync reports these as **Protected**. A trailing `/`
protects a whole folder. Your additions survive syncs — the script only rewrites `version`,
`commit`, and `syncedAt` in your local `initium.json`.

---

## Adopting Initium in an Existing Project

A repository that was not cloned from Initium can adopt it with the same script. Bootstrap
`.initium/` from a release (v1.5.0 or later), then sync:

```bash
git checkout -b chore/adopt-initium
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git
git fetch --no-tags skeleton "+refs/tags/v1.5.0:refs/initium/v1.5.0"
git restore --source=refs/initium/v1.5.0 --worktree -- .initium/
bash .initium/scripts/sync.sh --ref v1.5.0 --dry-run
bash .initium/scripts/sync.sh --ref v1.5.0
```

While `skeleton.commit` is not yet recorded, the sync runs in **adoption mode**:

- An existing file that Initium also owns is kept unless it is byte-identical to some Initium
  version (then it is simply updated). Kept files are listed as **Existing kept**.
- Missing `merge_required` files are added; existing ones go through the normal merge prompt.
- Missing project templates (`AGENTS.md`, `CLAUDE.md`, `agent.config.yaml`, `docs/context/`,
  `docs/architecture/`, …) are created. `README*`, `LICENSE`, `CHANGELOG.md`,
  `CODE_OF_CONDUCT.md`, and `.env` are never added.

Adoption mode ends once `initium.json` records the commit. From the next sync on, Initium-owned
files are updated normally — so add every "Existing kept" file you want to keep to your local
`project_owned` before that sync. The full walkthrough (conflicts, `AGENTS.md`/`CLAUDE.md`, CI,
`/init` on an existing codebase) is in
[docs/guides/existing-project.md](../../docs/guides/existing-project.md).

---

## How to Sync

### Option 0: Automatic weekly pull request (recommended)

`.github/workflows/initium-sync.yml` runs every Monday (and on demand from the Actions tab):

1. Resolves the target from `agent.config.yaml → initium_sync.channel` — `tags` follows released
   versions only (default), `main` follows every commit.
2. Runs `sync.sh --auto`: applies Initium-owned files, removes files Initium deleted (only when
   unmodified locally), updates `initium.json`, and runs the validator.
3. Opens a pull request on `chore/initium-sync-v<version>` whose description contains the
   manual-merge checklist, locally modified files that were kept, and the release notes.
   The PR is a **draft** when validation fails (usually a migration step is needed).

Nothing is merged automatically. Review the PR, merge the listed `merge_required` files
(`/sync-initium` on the PR branch does this for you), follow the release notes, then merge.

One-time setup in each derived repository:
- **Settings → Actions → General → Workflow permissions**: enable
  "Allow GitHub Actions to create and approve pull requests".
- Optional: PRs opened with the default `GITHUB_TOKEN` do not trigger other workflows, so CI
  will not run on them. Add a fine-grained token or GitHub App token with contents and
  pull-requests read/write as the `INITIUM_SYNC_TOKEN` secret if CI must run on sync PRs.
- To pause the PRs, set `initium_sync.auto_pr: false` (the weekly check still reports in the run summary).

Other CI systems (GitLab, Azure DevOps, Jenkins): schedule the same command and open a merge
request with its summary file —
`bash .initium/scripts/sync.sh --auto --summary initium-sync.md` (exit 0; outputs are written to
`$GITHUB_OUTPUT` only on GitHub).

**Local notice:** the Claude Code `SessionStart` hook runs
`node .initium/scripts/check-update.mjs --hook`. When a newer release exists, the agent mentions it
once and suggests `/sync-initium`. The result is cached in `.agent/state/` for
`initium_sync.check_interval_hours` (default 24); disable with `initium_sync.notify_local: false`.
Run it by hand any time: `node .initium/scripts/check-update.mjs` (exit 10 = update available).

### Option 1: Sync script

**macOS / Linux / Git Bash (WSL):**
```bash
bash .initium/scripts/sync.sh                 # Interactive
bash .initium/scripts/sync.sh --auto          # Non-interactive: apply Initium-owned files, skip merges
bash .initium/scripts/sync.sh --dry-run       # Preview only
bash .initium/scripts/sync.sh --check         # Exit 10 when an update is available
bash .initium/scripts/sync.sh --check --json  # Same, machine-readable
bash .initium/scripts/sync.sh --ref v1.2.0    # Pin a specific release (or branch)
bash .initium/scripts/sync.sh --channel main  # Follow main instead of release tags
bash .initium/scripts/sync.sh --auto --summary sync.md   # Markdown summary (PR body)
```

**Windows — PowerShell (recommended on Windows):**
```powershell
# One-time: allow script execution if not already set
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.\.initium\scripts\sync.ps1                # Interactive
.\.initium\scripts\sync.ps1 -Auto          # Non-interactive
.\.initium\scripts\sync.ps1 -DryRun        # Preview only
.\.initium\scripts\sync.ps1 -Check -Json   # Exit 10 when an update is available
.\.initium\scripts\sync.ps1 -Ref v1.2.0    # Pin a specific release
```

> No `jq` required — uses built-in `ConvertFrom-Json`. For merge-required files, opens VS Code
> diff (if available). The `--summary` option and GitHub outputs are bash-only (used by CI).

**Windows — CMD (no bash or WSL required):**
```bat
.initium\scripts\sync.cmd
.initium\scripts\sync.cmd --auto
.initium\scripts\sync.cmd --check --json
.initium\scripts\sync.cmd --ref v1.2.0
```

> `sync.cmd` delegates to `sync.ps1` via `pwsh` or `powershell.exe`, both of which are built
> into Windows. No bash, WSL, or `jq` required.

**Removed files.** When Initium deletes a file it owned, the sync deletes your copy only if it is
byte-identical to Initium's last version. If you changed it, the file is kept and reported so you
can move your additions elsewhere. Candidates come from `fileOwnership.removed` in the target
version plus the `skeleton_owned` list in your local `initium.json`.

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

# 2. Fetch a release tag into a private ref namespace (keeps your own tags clean)
git fetch --no-tags skeleton "+refs/tags/v1.2.0:refs/initium/v1.2.0"

# 3. Apply a specific file from Initium
git restore --source=refs/initium/v1.2.0 --worktree -- .claude/commands/loop.md

# 4. Apply an entire directory of skeleton-owned files
git restore --source=refs/initium/v1.2.0 --worktree -- .claude/skills/

# 5. Review a merge-required file
git diff refs/initium/v1.2.0:.continue/config.yaml .continue/config.yaml

# 6. Update .initium/initium.json manually
# Edit skeleton.commit and skeleton.syncedAt fields
```

---

## When to Sync

| Trigger | Frequency | Priority |
|---------|-----------|----------|
| Initium releases a new version (weekly PR opens automatically) | Within one sprint of release | High |
| New skill added (language/framework your team uses) | When you start using that tech | Medium |
| Security patch in skill rules | Within a week | High |
| New slash command added | As convenient | Low |
| Check for updates | Automatic (weekly workflow + session notice) | — |

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
vimdiff .continue/config.yaml <(git show refs/initium/v1.2.0:.continue/config.yaml)  # ref fetched by sync.sh
```

### `.cursor/mcp.json`

Initium adds new MCP server entries (always disabled by default).

**What to take from Initium:**
- New server entries like `jira`, `linear`, `slack`, `sentry`, `codegraph`
- Updated configurations for existing servers
- `sh` + `.initium/scripts/npx.sh` as the launcher (GUI editors often lack `npx` on `PATH`)

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

**Option B — Take ownership locally**
Add the path to `fileOwnership.project_owned` in your `.initium/initium.json`. The sync never
writes it again and lists it as **Protected**; compare with Initium's version when you want to
pick up improvements:
```bash
git show refs/initium/<tag>:<file> | diff -u - <file>
```

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

**Q: Can I add Initium to a repository that was not cloned from it?**
Yes — see [Adopting Initium in an Existing Project](#adopting-initium-in-an-existing-project).
The first sync keeps your existing files and only adds what is missing.

**Q: Will sync break my running application?**
No. The sync only touches AI configuration files (`.claude/`, `.cursor/`, `.continue/`,
`docs/`, `scripts/`). It never modifies your application source code, tests, or data.

**Q: What if I've modified a skeleton_owned file?**
Your modification will be overwritten. Either move your additions to a separate file,
or add the file to `project_owned` in your `.initium/initium.json` so the sync skips it.

**Q: Can I sync a specific file only?**
Yes: `git restore --source=refs/initium/<tag> --worktree -- .claude/commands/loop.md`

**Q: How do I roll back a bad sync?**
`git diff HEAD` shows what changed. `git checkout HEAD -- <files>` restores any file.
Or `git stash` before sync to have a quick escape hatch.

**Q: What if the Initium validator count increases after sync?**
New files were added to Initium. The updated validator checks for them.
Run `bash .initium/scripts/validate.sh` — any FAILs indicate missing new files.
The sync should have applied them; if not, apply manually.
