# Adding Initium to an Existing Project

> 🇹🇷 [Türkçe](existing-project.tr.md)

This guide is for teams that already have a repository — with code, CI, and their own
conventions — and want the Initium workflow (slash commands, rules, skills, agent docs)
without starting over. For a new project, clone Initium instead: see [onboarding.md](onboarding.md).

**Time:** 30–60 minutes, most of it reviewing what Initium proposes.
**Requires:** git, bash (or PowerShell on Windows), and Initium **v1.5.0 or later** — earlier
`sync.sh` versions overwrite existing files on the first sync.

---

## What Adoption Changes

The first sync runs in *adoption mode* because your repository has no recorded Initium commit
yet. In this mode it never replaces a file you already have.

| Initium file class | File missing in your repo | File already exists |
|--------------------|---------------------------|---------------------|
| `skeleton_owned` (commands, skills, rules, agent docs) | Added | Kept if it differs from every Initium version — listed as **Existing kept** |
| `merge_required` (`.gitignore`, `.editorconfig`, `SECURITY.md`, `ci.yml`, PR template, `.claude/settings.json`, `.cursor/mcp.json`, …) | Added | Diff shown, you choose (skipped in `--auto`) |
| `project_owned` templates (`AGENTS.md`, `CLAUDE.md`, `agent.config.yaml`, `docs/context/`, `docs/architecture/`, `.env.example`, …) | Added as TODO templates | Never touched |
| `README*`, `LICENSE`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, `.env` | Not added | Never touched |

Anything you list under `fileOwnership.project_owned` in your local `.initium/initium.json` is
never written — on this sync or any later one. It shows up as **Protected** in the summary.

Files most likely to collide in an existing repository: `CONTRIBUTING.md`, `SECURITY.md`,
`.editorconfig`, `.gitignore`, `.devcontainer/devcontainer.json`, `.github/workflows/ci.yml`,
`.github/PULL_REQUEST_TEMPLATE.md`, `.claude/settings.json`, `.cursor/rules/*.mdc`, `opencode.json`,
and an existing `AGENTS.md` or `CLAUDE.md`.

---

## Step 1 — Prepare a Branch

Start from a clean tree so every Initium change is reviewable as one diff.

```bash
git status                       # must be clean
git checkout -b chore/adopt-initium
```

---

## Step 2 — Bootstrap `.initium/`

`sync.sh` lives inside Initium, so fetch one release and restore only the `.initium/` folder.
Pick the latest release from the [releases page](https://github.com/mehmet-yildirim/Initium/releases).

```bash
INITIUM_TAG=v1.5.0               # latest release, v1.5.0 or later
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git
git fetch --no-tags skeleton "+refs/tags/$INITIUM_TAG:refs/initium/$INITIUM_TAG"
git restore --source="refs/initium/$INITIUM_TAG" --worktree -- .initium/
```

Windows (PowerShell):

```powershell
$InitiumTag = 'v1.5.0'
git remote add skeleton https://github.com/mehmet-yildirim/Initium.git
git fetch --no-tags skeleton "+refs/tags/${InitiumTag}:refs/initium/${InitiumTag}"
git restore --source="refs/initium/$InitiumTag" --worktree -- .initium/
```

Fetched Initium refs live under `refs/initium/`, so they never mix with your own tags or branches.

**Optional — protect files before the first sync.** If you already know that some files must
stay yours even when Initium updates them later (a custom `CONTRIBUTING.md`, your own
`.cursor/rules/01-coding-standards.mdc`), add them to `project_owned` in `.initium/initium.json`
now. A trailing `/` protects a whole folder.

```json
"project_owned": [
  "AGENTS.md",
  "CONTRIBUTING.md",
  ".cursor/rules/01-coding-standards.mdc",
  ...
]
```

---

## Step 3 — Preview, Then Sync

```bash
bash .initium/scripts/sync.sh --ref "$INITIUM_TAG" --dry-run    # shows every add / keep / merge
bash .initium/scripts/sync.sh --ref "$INITIUM_TAG"              # applies; asks per merge_required file
```

Windows: `.initium\scripts\sync.cmd --ref v1.5.0 --dry-run`, then without `--dry-run`.

For `merge_required` files that already exist, the interactive sync shows a diff and offers
`a` (overwrite with Initium's version), `s` (skip — the default), or `o` (open both in
`$VISUAL`). **Skip anything you are not sure about** — you merge it by hand in Step 5.

At the end the summary lists four groups: applied, skipped (merge by hand), **Protected**, and
**Existing kept**. Keep that output open for the next step.

---

## Step 4 — Decide on Every "Existing kept" File

Each entry is a file Initium also ships, where your version won. For each one:

```bash
git show "refs/initium/$INITIUM_TAG:<file>" | diff -u - <file>    # Initium's vs yours
```

- **Keep yours permanently** → add the path to `project_owned` in `.initium/initium.json`.
  Otherwise the next sync (no longer in adoption mode) replaces it with Initium's version.
- **Take Initium's** → `git checkout "refs/initium/$INITIUM_TAG" -- <file>`
- **Combine** → edit your file to include what you need from Initium's, then add it to
  `project_owned` so future syncs leave it alone.

Typical decisions:

| File | Usual choice |
|------|--------------|
| `CONTRIBUTING.md`, `.devcontainer/devcontainer.json` | Keep yours → `project_owned` |
| `.cursor/rules/01-…05-*.mdc` with the same name as your own rules | Rename yours (`10-team-*.mdc`), take Initium's |
| `opencode.json` | Combine — keep your providers, add Initium's `instructions` and command paths |
| `docs/guides/team.md` | Take Initium's, or `project_owned` if you already document roles |

---

## Step 5 — Merge the Shared Configuration Files

These are the `merge_required` files that existed before and were skipped:

- **`.gitignore`** — at minimum append the "AI tool — local overrides & runtime state" block
  (`.agent/state/`, `.agent/audit/`, `.agent/escalations/`, `.agent/outputs/`, `.agent/STOP`,
  `.claude/settings.local.json`, `.codebase-memory/`) and make sure `.env` is ignored. See the
  full file with `git show "refs/initium/$INITIUM_TAG:.gitignore"`.
- **`.claude/settings.json`, `.cursor/mcp.json`, `.continue/config.yaml`** — keep your entries,
  add Initium's permissions, hooks, and MCP servers you want. Keep the `PreToolUse` guardrail
  entry in `.claude/settings.json`.
- **`.cursor/hooks.json`** — add Initium's three guardrail entries next to your own hooks.
- **Git hooks** — Initium's pre-commit guardrail lives in `.githooks/`. Without another hook
  manager, run `git config core.hooksPath .githooks` (hooks already in `.git/hooks/pre-commit`
  keep running after it). With husky, lefthook, or pre-commit, keep your setup and call
  `sh .githooks/pre-commit` from your pre-commit hook. See
  [guardrails.md](../../.initium/docs/guardrails.md).
- **`SECURITY.md`, `.editorconfig`, PR and issue templates** — keep yours unless Initium's adds
  something missing (the PR checklist is referenced by `/review` and `/qa`).

---

## Step 6 — Reconcile `AGENTS.md` and `CLAUDE.md`

Initium keeps every agent on one instruction file: `AGENTS.md`, read natively by Cursor,
OpenCode, Codex, Copilot, and Gemini CLI. `CLAUDE.md` only imports it.

| You had | Do this |
|---------|---------|
| Neither | Nothing — the sync added both templates; `/init` fills them in Step 8 |
| `AGENTS.md` only | Keep it. Add the missing Initium sections (Essential Commands, Architecture, Testing Standards, Git & PR Workflow, Do Not) — `/init` appends them without rewriting your text |
| `CLAUDE.md` with project rules | Move the rules into `AGENTS.md`, then make `CLAUDE.md` the import stub below, keeping only Claude Code–specific notes under it |
| `.cursorrules` or old `.cursor/rules` | Move project facts into `AGENTS.md` / `00-project-overview.mdc`; keep team rules as numbered `.mdc` files that don't clash with `01–05` |

```markdown
@AGENTS.md

<!-- Claude Code-only instructions below; everything else goes in AGENTS.md. -->
```

---

## Step 7 — Review the Workflows Initium Added

If your repository had no file at the same path, the sync added:

- **`.github/workflows/ci.yml`** — a generic placeholder. If you already have CI under another
  name, delete it (and consider adding dependency review and SHA-pinned actions to your own
  workflow). If you have none, generate a real one with `/init ci: <your stack>`.
- **`.github/workflows/initium-sync.yml`** — opens a weekly PR with Initium updates. Keep it to
  stay current, or delete it and run `sync.sh` by hand. Configure it in `agent.config.yaml →
  initium_sync`.

---

## Step 8 — Describe the Project with `/init`

Open the repository in Claude Code (or Cursor / OpenCode) and run:

```
/init
```

With no arguments, `/init` treats the repository as an existing codebase: it reads your
manifests, scripts, directory tree, and CI to fill `AGENTS.md`, `00-project-overview.mdc`,
`docs/context/`, and `docs/architecture/overview.md` with what actually exists. It only replaces
`TODO` placeholders, never edits existing CI, and records gaps against the architecture rules
as "Known deviations" instead of proposing a rewrite. Add a sentence of business context if the
code alone does not explain it:

```
/init existing: Billing service for the Acme storefront, owned by the payments team
```

Then:

- `/codegraph setup` — recommended for large codebases, so agents query symbols and callers
  instead of reading whole files.
- `/skill list` — confirm the skills that match your stack; write team-specific ones with
  `/skill new project-<topic>`.
- `bash .initium/scripts/init.sh` — optional wizard for `agent.config.yaml` (tracker,
  escalation channels, domain keywords) if you plan to run the autonomous agent.
- Delete templates you will not use (for example `DESIGN.md` / `PRODUCT.md` in a backend-only
  service).

---

## Step 9 — Validate and Open the PR

```bash
bash .initium/scripts/validate.sh     # remaining TODOs are warnings, not failures
git add -A
git commit -m "chore: adopt Initium $INITIUM_TAG"
```

Open a PR from `chore/adopt-initium`. Reviewers should focus on the `merge_required` files, the
`project_owned` list in `.initium/initium.json`, and the content `/init` generated.

---

## After Adoption

- Updates arrive through `initium-sync.yml` PRs or `bash .initium/scripts/sync.sh`
  (`/sync-initium` in Claude Code). See [sync-guide.md](../../.initium/docs/sync-guide.md).
- From the second sync on, adoption mode is off: Initium-owned files that are not in your
  `project_owned` list are updated to Initium's version. That is why Step 4 matters.
- New team members follow [onboarding.md](onboarding.md) from "Setting Up AI Tools" onward.

## Monorepos

Install Initium once at the repository root. Describe each service in `AGENTS.md`'s repository
layout, and add per-package detail as nested `AGENTS.md` files (agents read the nearest one) or
as `project-<service>` skills scoped with path globs.

## Removing Initium

Delete `.initium/`, `.claude/commands/`, `.claude/skills/`, `.opencode/commands/`,
`.cursor/rules/0[1-5]-*.mdc`, `.continue/rules/`, `.agent-templates/`, `.githooks/`, the guardrail
hook entries in `.claude/settings.json` and `.cursor/hooks.json`, and the Initium workflows; run
`git config --unset core.hooksPath` if it points to `.githooks`, then `git remote remove skeleton` and `git for-each-ref --format='delete %(refname)' refs/initium/ | git update-ref --stdin`.
Keep `AGENTS.md` — it is useful without Initium.
