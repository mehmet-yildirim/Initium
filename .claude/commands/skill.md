Create, update, or list project skills in the Agent Skills format (`SKILL.md`).
Skills live in `.claude/skills/<name>/SKILL.md` and are loaded natively by Claude Code, Cursor,
and OpenCode. Only the `name` and `description` are always in context; the body loads on demand,
so a precise description matters more than anything else in the file.

Modes (from `$ARGUMENTS`):
- `new <topic>` — create a new skill (default)
- `update <name>` — improve an existing skill
- `list` — list skills with their descriptions and path scopes

---

## new <topic>

1. **Check for overlap.** List existing skills (`.claude/skills/*/SKILL.md`). If an existing skill
   covers most of the topic, switch to `update` instead of creating a near-duplicate.
2. **Decide if it should be a skill.** A skill holds procedural or stack-specific knowledge the
   agent needs only sometimes. Project-wide facts belong in `AGENTS.md`; a repeatable
   multi-step workflow the user triggers explicitly belongs in `.claude/commands/`.
3. **Gather the knowledge from the codebase**, not from generic advice: existing conventions,
   libraries in use, folder structure, patterns in recent code, lint configuration, and
   decisions in `docs/architecture/decisions/`. Ask the developer for anything that cannot be
   inferred.
4. **Name it.** Lowercase letters, digits, single hyphens, max 64 characters, matching the folder
   name. Follow the existing prefixes: `lang-`, `fe-`, `be-`, `mobile-`, `devops-`, `db-`,
   `security-`, `docs-`, `ai-`, or `project-` for project-specific skills.
5. **Write `.claude/skills/<name>/SKILL.md`:**
   ```markdown
   ---
   name: <name>
   description: <What it covers — key tools and patterns. Use when <concrete trigger>.>
   paths:
     - "<glob for files this applies to>"
   ---

   # <Title>

   ## <Section per concern: structure, patterns, errors, security, testing>
   - Imperative, specific, checkable rules
   ```
   - `description`: 1–1024 characters; state *what* and *when to use it* with concrete triggers.
   - `paths`: optional; add globs when the skill applies to specific file types, omit it when the
     skill is task-triggered (for example "writing a migration").
   - Body: rules the agent can follow and a reviewer can verify. Target under 200 lines; move long
     reference material to `references/*.md` inside the skill folder and link to it.
   - Never include secrets, internal URLs with credentials, or personal data.
6. **Regenerate derived files and validate:**
   ```bash
   node .initium/scripts/sync-skills.mjs
   ```
   This validates the frontmatter and regenerates the Continue rule in `.continue/rules/skills/`.
   For Continue, the developer still activates the rule in `.continue/config.yaml`.
7. **Register it** in `skills/README.md` under the right category.

## update <name>

- Read the skill and the code it governs; remove rules the codebase no longer follows, add rules
  for patterns that emerged, tighten the description if the agent loads it at the wrong time.
- Run `node .initium/scripts/sync-skills.mjs` afterwards.
- Skills shipped by Initium (listed as `skeleton_owned` in `.initium/initium.json`) are
  overwritten by `/sync-initium`. Put project-specific additions in a separate `project-<topic>`
  skill instead of editing them.

## list

Print a table of skill name, description (first sentence), and `paths` scope, grouped by prefix.

---

Skill request: $ARGUMENTS
