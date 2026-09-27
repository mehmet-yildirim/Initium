Set up, check, and query the project's code knowledge graph so agents navigate code
structurally instead of grepping and reading whole files. Cuts context tokens on every task.

The graph is provided by an MCP server behind a provider setting in `agent.config.yaml →
codegraph`. The default provider is `codebase-memory-mcp` (tree-sitter + LSP hybrid, SQLite,
background watcher with git-based incremental re-indexing).

Subcommands: `setup` | `status` | `query <symbol or question>` | `impact [file|symbol]` | `refresh`
Default when no argument is given: `status`.

---

## setup

1. Branch check: config changes go on a `chore/` branch.
2. Install the provider once per machine (it auto-configures detected clients — Claude Code,
   Cursor, OpenCode — and needs no API key):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
   # or: npm install -g codebase-memory-mcp
   codebase-memory-mcp config set auto_index true
   ```
   Tell the developer to review the installer before piping it to a shell, and to restart
   their agent session after installation.
3. Create or update `.cbmignore` (gitignore syntax) so secrets and noise are never indexed:
   ```
   .env
   .env.*
   **/secrets/**
   *.pem
   *.key
   .agent/
   dist/
   build/
   coverage/
   ```
4. `agent.config.yaml` is a protected path: ask the developer to set `codegraph.enabled: true`
   there rather than editing it yourself. If the team wants to share the graph
   snapshot, set `codegraph.share_artifact: true` and remove `.codebase-memory/` from
   `.gitignore` — but commit the artifact on a cadence (release or nightly), never on every
   change: each refresh is a full new blob in git history.
5. If the client was not auto-configured, enable the disabled `codegraph` entry in
   `.cursor/mcp.json` and `opencode.json` (`"enabled": true`).
6. Index: call `index_repository` with the absolute repository path, then `get_graph_schema`
   and `get_architecture` to confirm nodes, edges, languages, and routes.

## status

- Call `index_status` and `check_index_coverage` for the repository.
- Report: indexed yes/no, node and edge counts, last update, stale or skipped paths, and whether
  the watcher is active.
- If not indexed or stale, recommend `/codegraph refresh`.

## query <symbol or question>

Answer using the graph, in this order, and stop as soon as the question is answered:

1. `search_graph` to resolve names (use a regex like `.*Partial.*` if the exact name is unknown).
2. `trace_path` for callers/callees (depth 1–3; go deeper only when needed).
3. `get_file_outline` for structure of a single file.
4. `get_code_snippet` for the body of the specific symbols that matter.

Only read whole files when a snippet is insufficient. Report the answer with file paths and line
references, plus how many files were read in full.

## impact [file|symbol]

- With no argument: call `detect_changes` to map the current git diff to affected symbols with
  risk classification.
- With a symbol: `trace_path` inbound to depth 3 to list callers, then identify tests that cover
  those callers.
- Output: affected symbols, affected HTTP routes and services, risk level, and the minimal test
  set to run. `/qa` and `/review` can use this as their scope.

## refresh

- Call `index_repository` for the repository (incremental — only changed files are re-parsed).
- Use after large merges, branch switches, or when `status` reports stale coverage.

---

## Rules

- Never index or return content from files matched by `.cbmignore` or `safety.protected_paths`.
- The graph can be stale; if a result contradicts the file on disk, trust the file and run
  `refresh`.
- If the MCP server is unavailable, say so and fall back to targeted search — do not silently
  read the whole codebase.

---

Subcommand and arguments: $ARGUMENTS
