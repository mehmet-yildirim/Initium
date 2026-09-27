Check for and apply updates from Initium into this derived project.
Preserves all project-specific customizations while pulling in improved AI rules,
new slash commands, updated skill files, and bug fixes from upstream Initium.

This command orchestrates the full sync: fetch → classify → apply → validate.

---

## Step 1: Read Current Sync State

Read `.initium/initium.json`:
- `skeleton.repository` — the upstream Initium URL
- `skeleton.commit` — the commit this project last synced from
- `skeleton.syncedAt` — when the last sync ran
- `skeleton.version` — Initium version string

If `.initium/initium.json` doesn't exist, this project was not initialized from Initium
with proper tracking. Add it manually (see `.initium/docs/sync-guide.md`).

---

## Step 2: Fetch Initium Updates

```bash
# Add skeleton remote if not present
git remote get-url skeleton 2>/dev/null || \
  git remote add skeleton "$(jq -r '.skeleton.repository' .initium/initium.json)"

# Fetch latest
git fetch skeleton --quiet

LATEST_COMMIT=$(git rev-parse skeleton/main)
CURRENT_COMMIT=$(jq -r '.skeleton.commit' .initium/initium.json)
```

If `LATEST_COMMIT == CURRENT_COMMIT`, report "Already up to date" and stop.

Otherwise, show the changes:
```bash
git log --oneline "$CURRENT_COMMIT..skeleton/main"
```

And point to `.initium/docs/UPDATES.md` on the Initium repo for the full migration guide.

---

## Step 3: Classify Changed Files

Read the ownership lists from `.initium/initium.json`:

| Category | Behaviour |
|----------|-----------|
| `skeleton_owned` | Auto-apply — safe to overwrite, no project content |
| `merge_required` | Show diff — project has customised these |
| `project_owned` | Skip and report — never modify |

Get files changed since last sync:
```bash
git diff --name-only "$CURRENT_COMMIT" skeleton/main
```

For each changed file, determine its category from `.initium/initium.json`.

---

## Step 4: Apply skeleton_owned Files

For every file in `skeleton_owned` that changed:
```bash
# Extract from Initium remote and overwrite local copy
git show skeleton/main:<file> > <file>
```

These files are safe to overwrite because they contain no project-specific content:
- All `.claude/commands/` slash commands
- All `.opencode/commands/` OpenCode mirrors (keep in sync via `.initium/scripts/sync-opencode-commands.sh` when editing locally)
- All `.cursor/rules/skills/` and `.continue/rules/skills/` files
- All `docs/guides/agent/` documentation
- All `scripts/` utility scripts

**Exception:** Check if any file in `skeleton_owned` was deleted in Initium.
If so, warn the developer and ask if they want to remove it locally too.

---

## Step 5: Handle merge_required Files

For each merge-required file that changed, produce a side-by-side diff:

```bash
git diff skeleton/main:<file> <file>
```

For each, present three options:
1. **Overwrite** — take the Initium version entirely (use when you haven't customized the file)
2. **Diff tool** — open in your configured diff editor to cherry-pick changes
3. **Skip** — leave as is; developer merges manually later

**Key merge_required files and what to look for:**

### `.continue/config.yaml`
Initium adds new skill sections and slash commands. Merge strategy:
- Keep your API keys and model configuration
- Add any new `# --- X skills ---` comment blocks from Initium
- Add any new slash command entries from Initium
- Don't remove your existing uncommented skill activations

### `.cursor/mcp.json`
Initium may add new MCP server entries. Merge strategy:
- Keep any servers you've enabled (removed `"disabled": true`)
- Add new Initium server entries (they ship with `"disabled": true`)

### `.claude/settings.json`
Initium adds new hook definitions. Merge strategy:
- Keep your existing permission allow/deny rules
- Add any new hook entries from Initium

### `.github/workflows/ci.yml`
Initium may fix or add CI steps. Merge strategy:
- Keep your project-specific job configurations
- Adopt Initium improvements to existing job structure

### `docs/guides/ai-workflow.md` and `docs/guides/onboarding.md`
Initium adds new command references. Merge strategy:
- Keep your project-specific workflows and examples
- Add new command rows to the reference tables
- Don't overwrite project-specific notes you've added

---

## Step 6: Report project_owned Changes (Informational)

If any `project_owned` files changed in Initium (e.g., `AGENTS.md` template was
improved), report them as informational notices:

```
ℹ  AGENTS.md — Initium template improved
   Review: git show skeleton/main:AGENTS.md
   Action: Manually adopt any new guidance that applies to your project
```

Do NOT apply these files automatically.

---

## Step 7: Update .initium/initium.json

After applying changes, update the tracking fields:

```bash
jq --arg commit "$LATEST_COMMIT" \
   --arg date "$(date +%Y-%m-%d)" \
   --arg ver "$NEW_VERSION" \
   '.skeleton.commit = $commit | .skeleton.syncedAt = $date | .skeleton.version = $ver' \
   .initium/initium.json > tmp && mv tmp .initium/initium.json
```

---

## Step 8: Run Validator

```bash
bash .initium/scripts/validate.sh
```

All PASS counts should be ≥ what they were before the sync. Any new FAILs indicate
a file that was expected by Initium but not applied (e.g., due to merge conflicts).

---

## Step 9: Summary and Next Steps

Report:
```
Sync Summary
  Applied (auto)   : N files (skeleton_owned)
  Merged manually  : N files
  Skipped          : N files — merge these manually
  Notices          : N project-owned template changes to review

Suggested commit:
  git add -p
  git commit -m "chore: sync Initium to vX.Y.Z (<short-sha>)"
```

---

## What This Command Does NOT Do

- Modify your application source code
- Change `AGENTS.md`, `agent.config.yaml`, or any project context files
- Affect the `.agent/` runtime directory
- Push to any remote (you decide when to commit and push)

---

Options (pass as arguments): `--auto` | `--dry-run` | `--check`
