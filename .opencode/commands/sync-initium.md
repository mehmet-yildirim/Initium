Check for and apply updates from Initium into this derived project.
Preserves all project-specific customizations while pulling in improved AI rules,
new slash commands, updated skills, and bug fixes from upstream Initium.

The sync script does the mechanical work (fetch → classify → apply → remove → record).
Your job is to run it, then merge the `merge_required` files intelligently and verify.

Options (from `$ARGUMENTS`): `--check` | `--dry-run` | `--auto` | `--ref <tag|branch>` | `--channel tags|main`

---

## Step 0: Branch

Syncs go on their own branch: `chore/initium-sync-<version>`. Never sync on `main` / `develop`.
If a weekly `chore/initium-sync-v*` pull request (from `.github/workflows/initium-sync.yml`) is
already open, check it out and continue from Step 3 instead of syncing again.

## Step 1: Check

```bash
bash .initium/scripts/sync.sh --check        # Windows: .\.initium\scripts\sync.ps1 -Check
```

Exit code `0` = up to date (report and stop), `10` = update available.
The target follows `agent.config.yaml → initium_sync.channel` — `tags` (latest release,
default) or `main`. Pass `--ref <tag>` to pin a specific version.

With `--check`, stop here and report current version, latest version, and the UPDATES.md
sections in between.

## Step 2: Preview, then apply

```bash
bash .initium/scripts/sync.sh --dry-run      # show what would change
bash .initium/scripts/sync.sh --auto --summary .agent/outputs/initium-sync.md
```

The script:
- overwrites changed `skeleton_owned` files and adds new ones
- deletes files Initium removed — **only if identical to Initium's last version**; locally
  modified copies are kept and listed
- skips `merge_required` files (listed for Step 3) and never touches `project_owned` files
- updates `.initium/initium.json` (version, commit, syncedAt) and runs the validator

Read the summary file: it contains the manual-merge checklist and the release notes.

## Step 3: Merge `merge_required` files

For each file in the summary's "Merge manually" list, compare both versions:

```bash
git diff refs/initium/<target-ref>:<file> <file>
```

Merge semantically — keep project customizations, adopt Initium's new sections:

| File | Keep from project | Take from Initium |
|------|-------------------|-------------------|
| `.continue/config.yaml` | API keys, models, activated skills | New commented skill entries, new slash commands |
| `.cursor/mcp.json` | Servers you enabled, env references | New server entries (ship `"disabled": true`) |
| `.claude/settings.json` | Permission allow/deny rules | New hook entries |
| `.github/workflows/ci.yml` | Stack-specific jobs | Fixes to generic job structure |
| `.gitignore` | Project ignores | New generated-file patterns |
| `docs/guides/*.md` | Project-specific notes | New command references |

`agent.config.yaml` is project-owned and protected: list new sections from the release notes
for the developer to add; do not edit it yourself.

## Step 4: Follow the release notes

Apply every **Migration Notes** step from the UPDATES.md sections in the summary (for example
renaming files that are project-owned). Report any step that needs a human decision.

For files listed as "Removed in Initium but modified locally", move project-specific content to
its new home (for example a `.claude/skills/project-<topic>/SKILL.md`) and delete the old file.

## Step 5: Verify and report

```bash
bash .initium/scripts/validate.sh
node .initium/scripts/sync-skills.mjs --check
bash .initium/scripts/sync-opencode-commands.sh --check
```

Report:
```
Initium sync: vOLD → vNEW
  Applied (auto)   : N files (M removed)
  Merged manually  : N files
  Needs a human    : <migration steps or conflicts you could not resolve>
Suggested commit: chore: sync Initium to vNEW
```

---

## What This Command Does NOT Do

- Modify application source code
- Change `AGENTS.md`, `agent.config.yaml`, or project context files without the developer
- Push, open a PR, or merge (you decide when to commit and push)

---

Arguments: $ARGUMENTS
