# Guardrails

Initium ships one guardrail policy that every agent tool enforces **before** a command runs or
a file is read or written, plus a git pre-commit hook that checks what actually gets committed.
The rules come from a built-in baseline and the `safety:` section of `agent.config.yaml`.

Guardrails are defense in depth. They stop the common ways an agent leaks a secret, wrecks a
branch, or edits files it must not touch — they are not a sandbox. Run unattended agents in the
container ([docker-agent.md](agent/docker-agent.md)) with least-privilege tokens as well.

---

## Where they run

| Layer | File | Checks |
|-------|------|--------|
| Claude Code | `.claude/hooks/guardrails.mjs` (`PreToolUse` in `.claude/settings.json`) | Bash, Read/Grep/Glob/LS, Write/Edit/MultiEdit/NotebookEdit |
| Cursor | `.cursor/hooks/guardrails.mjs` (`.cursor/hooks.json`) | `beforeShellExecution`, `beforeReadFile`, `preToolUse` for Write/Delete |
| OpenCode | `.opencode/plugins/initium-guardrails.js` (auto-loaded) | bash, read/grep/glob/list, write/edit/patch |
| Git | `.githooks/pre-commit` → `.initium/guardrails/pre-commit.mjs` | staged files and added lines — applies to humans and every tool |

All four call the same engine in `.initium/guardrails/` (`policy.mjs`), so a rule behaves the
same everywhere. Claude Code runs the hook even with `--dangerously-skip-permissions`.

Enable the git layer once per clone (`setup.sh` / `setup.ps1` and the Docker entrypoints do it
for you):

```bash
git config core.hooksPath .githooks
```

A hook that already lived in `.git/hooks/pre-commit` keeps running after the guardrail check.

---

## Modes

| | Interactive (default) | Autonomous (`INITIUM_AGENT_MODE=autonomous`) |
|---|---|---|
| Baseline violations | deny | deny |
| Secret file reads | deny | deny |
| "Needs a human" rules | ask | **deny** |
| Writes outside the project | allowed | denied (temp dirs and `/dev/null` allowed) |
| Kill switch (`safety.kill_switch_file`) | ignored | every command and write denied |
| PR size limits (pre-commit) | warning | **block** |
| Protected paths (pre-commit) | allowed | **block** |
| Hook crashes or Node.js missing | allowed with a warning | **deny** |

The Docker services, `groom-runner.sh`, and the webhook receiver set autonomous mode
themselves; the systemd examples in [jira-server-setup.md](agent/jira-server-setup.md) set it
with `Environment=INITIUM_AGENT_MODE=autonomous`. Set it for any other unattended runner.

"Ask" means: Claude Code shows its permission prompt; Cursor asks for shell commands. Cursor
cannot ask for file writes and OpenCode cannot ask at all, so there an interactive "ask" is
allowed and recorded in the audit log.

---

## Rules

### Baseline (always on, not configurable)

- **Destructive delete** — recursive `rm` of `/`, `~`, `$HOME`, `.`, `..`, `*`, or with `--no-preserve-root`
- **Protected branches** — force push (including `--force-with-lease` and `+ref`), delete, or `--mirror`
  touching `main`, `master`, `develop`, or `release/*`; a bare `git push -f` without a ref
- **Hook bypass** — `--no-verify`, `git commit -n`, and any `core.hooksPath` change (`git config`, `git -c`)
- **System destruction** — `mkfs`, `dd of=/dev/…`, `chmod -R … /`
- **Remote scripts** — `curl … | sh`, `wget … | python`, `bash -c "$(curl …)"`
- **`DROP DATABASE`**
- **Secret files** — reading them with any tool (`cat`, `grep`, `base64`, `<` redirection, the Read tool, …)
- **`.git/` internals** — writing inside `.git/`

Secret files: `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`,
SSH private keys, `.ssh/`, `.aws/credentials`, `.docker/config.json`, `.netrc`, `.pgpass`,
`secrets/`, service-account JSON, `*.tfvars`, kubeconfig. Templates stay readable:
`.env.example`, `.env.sample`, `.env.template`, `.env.dist`, `*.pub`, `*.tfvars.example`.

### Needs a human (ask → deny when autonomous)

- Commands containing an entry of `safety.forbidden_commands` (case-insensitive substring)
- Dumping the environment (`env`, `printenv`, `export -p`, `/proc/*/environ`) or echoing
  variables named `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*API_KEY*`, …
- Writing a secret file, a `safety.protected_paths` match, or a guardrail file
  (`.initium/guardrails/`, `.githooks/`, hook configs, `agent.config.yaml`)

### Pre-commit

- Staged secret files (`safety.forbidden_file_patterns` added to the list above) — blocked
- Added lines that look like a private key, AWS / GitHub / Anthropic / OpenAI / Slack / Google /
  Stripe live credential — blocked. Add `guardrails:allow` to the line for a false positive.
- `safety.protected_paths` and guardrail files — blocked in autonomous mode
- Branch size against `origin/main` (or `INITIUM_BASE_BRANCH`) above `max_files_per_pr` /
  `max_lines_per_pr` — warning, blocked in autonomous mode

---

## Configuration

Everything project-specific lives in `agent.config.yaml`:

```yaml
safety:
  protected_paths: [".github/workflows/**", "**/.env", "agent.config.yaml", "AGENTS.md"]
  forbidden_file_patterns: ["*.pem", "*.key", ".env", ".env.*"]
  forbidden_commands: ["rm -rf", "DROP TABLE", "DROP DATABASE", "git push --force"]
  max_files_per_pr: 30
  max_lines_per_pr: 1000
  kill_switch_file: ".agent/STOP"
```

Patterns follow `.gitignore` rules: no `/` matches the file name anywhere, `**` spans directories.

| Variable | Effect |
|----------|--------|
| `INITIUM_AGENT_MODE=autonomous` | Unattended mode (see above) |
| `INITIUM_GUARDRAILS=warn` | Pre-commit reports instead of blocking — for humans; ignored in autonomous mode |
| `INITIUM_BASE_BRANCH` | Base ref for PR size limits (default: first of `origin/main`, `main`, `origin/master`, `master`) |
| `INITIUM_NODE` | Path to the `node` binary when an editor cannot find it |

---

## Audit log

Every deny and every "ask" is appended to `.agent/audit/<date>-guardrails.jsonl` with the
tool, mode, rule, and a truncated target (never file contents). `.agent/audit/` is gitignored.

```bash
jq -r '[.timestamp, .adapter, .decision, .rule, .target] | @tsv' .agent/audit/*-guardrails.jsonl
```

---

## Using another hook manager

If the project already sets `core.hooksPath` (husky, lefthook, pre-commit), keep it and call the
guardrail from your pre-commit hook:

```bash
# .husky/pre-commit
sh .githooks/pre-commit
```

```yaml
# lefthook.yml
pre-commit:
  commands:
    initium-guardrails:
      run: sh .githooks/pre-commit
```

---

## Troubleshooting

**Cursor blocks every tool with "command not found: node".** Cursor launched from the Dock
does not inherit your shell `PATH`. The hooks run through `.initium/guardrails/node.sh`, which
probes nvm, Volta, Homebrew, mise, and asdf; if Node lives elsewhere, set `INITIUM_NODE` in the
environment Cursor starts with.

**A legitimate command is blocked.** Check the rule in the message or the audit log. Rules from
`agent.config.yaml` can be narrowed there; baseline rules are intentional — run the command
yourself in a terminal.

**A commit is blocked by a false-positive token.** Add `guardrails:allow` to that line, or
commit once with `INITIUM_GUARDRAILS=warn git commit …`.

**Tests**

```bash
node --test ".initium/guardrails/test/*.test.mjs"
```

---

## Limits

- Shell analysis is best-effort: it unwraps `sudo`, `env`, `sh -c`, `eval`, `$(…)`, and
  backticks, but a script file the agent writes and then runs is opaque to it.
- The engine sees paths, not contents: a secret copied into an ordinary file is caught only by
  the pre-commit token scan.
- Tools without hooks (Continue, plain terminals) are covered only by the pre-commit layer.
