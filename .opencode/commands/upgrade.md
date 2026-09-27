Plan and execute a dependency, framework, language, or runtime upgrade safely.

Modes (from `$ARGUMENTS`):
- `audit` — report outdated and vulnerable dependencies; change nothing (default when empty)
- `<package> [version]` — upgrade one dependency or framework
- `security` — apply only upgrades that fix known vulnerabilities
- `runtime <name> <version>` — upgrade a language runtime or toolchain (Node, JDK, Python, Go, .NET, Rust)

---

## Step 1: Inventory

Detect package managers and manifests (package.json + lockfile, pyproject/requirements, go.mod,
pom.xml / build.gradle(.kts) / version catalog, *.csproj, Cargo.toml, composer.json, pubspec.yaml,
Podfile, Dockerfile base images, CI tool versions).

Run the ecosystem's native outdated and audit commands, for example:
`npm outdated` / `npm audit`, `pip list --outdated` / `pip-audit`, `go list -m -u all` /
`govulncheck ./...`, `./gradlew dependencyUpdates`, `dotnet list package --outdated --vulnerable`,
`cargo outdated` / `cargo deny check advisories`, `composer outdated` / `composer audit`.

For `audit` mode, stop here and report a table: package, current, latest, type of bump
(patch/minor/major), known CVEs, and recommended action.

## Step 2: Research the change

For each major upgrade:
- Read the official changelog, release notes, and migration guide for every version crossed —
  not only the latest one.
- List breaking changes that apply to this codebase. If `codegraph.enabled` is `true`, use
  `search_graph` / `search_code` to find every usage of removed or changed APIs.
- Check peer dependencies and transitive constraints; note the minimum runtime version required.
- Check license changes; flag any move to a license incompatible with the project.

Produce a plan: order of upgrades (runtime → framework → libraries), code changes per breaking
change, and a rollback path. Escalate with `/escalate` before proceeding if the upgrade touches
authentication, payments, data migrations, or more than `safety.max_files_per_pr` files.

## Step 3: Execute in small increments

- Branch: `chore/upgrade-<package>-<version>`.
- One logical upgrade per commit: bump version → regenerate lockfile with the package manager
  (never hand-edit lockfiles) → apply code migrations → run tests.
- Prefer official codemods / migration tools when they exist (for example framework CLI
  `upgrade` commands, OpenRewrite recipes, `dotnet-upgrade`), then review their diff.
- Update Dockerfile base images, CI tool versions, and `.tool-versions` / toolchain files to match.

## Step 4: Verify

- Full test suite, lint, type-check, and build pass.
- Re-run the audit command: no new vulnerabilities introduced.
- Start the application (or run smoke tests) to catch runtime-only failures such as changed
  defaults or removed configuration keys.
- For framework majors, run `/qa` before opening the PR.

## Step 5: Report

- Table of upgrades performed, breaking changes handled, codemods used, and residual deprecation
  warnings.
- PR description links each migration guide used.

---

Upgrade request: $ARGUMENTS
