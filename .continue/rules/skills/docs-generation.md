---
name: docs-generation
description: Documentation-as-code standards — Diátaxis structure, README and CHANGELOG (Keep a Changelog) conventions, ADRs (MADR 4), API reference generation (TypeDoc 0.28, Sphinx/mkdocstrings, Dokka, DocC, Javadoc), OpenAPI 3.1/3.2 descriptions, Mermaid/C4 diagrams, docs sites (Starlight, Docusaurus), and docs CI (Vale, markdownlint, lychee, lefthook/pre-commit). Use when writing or reviewing docs, doc comments, READMEs, changelogs, ADRs, architecture diagrams, or documentation tooling and pipelines.
globs:
  - "**/docs/**/*.md"
  - "**/mkdocs.yml"
  - "**/CHANGELOG.md"
  - "**/adr/**"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Documentation as Code

Docs live in the repository, are reviewed like code, and are built and checked in CI. API
contract design (status codes, RFC 9457 errors, versioning) is in `api-rest-openapi`; language
doc-comment idioms are summarized in `reference/code-comments.md`.

## Baseline

- Structure: **Diátaxis** — tutorials, how-to guides, reference, explanation. Every page is one
  type; do not mix a tutorial with reference tables.
- Changelog: **Keep a Changelog** format with SemVer; generated drafts are curated by a human.
- Decisions: **ADRs** using MADR 4.0 (`docs/adr/NNNN-title-with-dashes.md`).
- API reference: generated from source (TypeDoc 0.28, Sphinx autodoc or mkdocstrings, Dokka 2,
  DocC, Javadoc, DocFX, `dart doc`, pkg.go.dev) — never hand-maintained.
- HTTP APIs: OpenAPI 3.1 (3.2 where tooling supports it), generated from code or used as the
  source of truth — one or the other, never both.
- Docs site: Starlight 0.42 (Astro) or Docusaurus 3.10. Material for MkDocs is in maintenance mode
  (critical fixes until May 2027) and MkDocs 1.x is unmaintained — do not start new sites on them;
  plan migration (Zensical is the Material team's successor) for existing ones.

## Structure

```
README.md               # what, why, quick start, links — the front door
CHANGELOG.md            # Keep a Changelog, newest first, [Unreleased] on top
CONTRIBUTING.md         # setup, workflow, conventions
SECURITY.md             # how to report vulnerabilities
docs/
├── tutorials/          # learning-oriented, runnable end to end
├── how-to/             # task-oriented recipes
├── reference/          # generated API docs, config and CLI reference
├── explanation/        # concepts, architecture overview, trade-offs
├── architecture/       # C4 diagrams (diagrams as code)
└── adr/                # architecture decision records
```

- Long-form docs go under `docs/`; source directories hold only doc comments and, where a module
  needs local context, a short `README.md` that links into `docs/`.

## Toolchain

| Concern | Tool |
|---|---|
| Markdown lint | markdownlint-cli2 (`.markdownlint.jsonc`) |
| Prose lint | Vale 3 (`.vale.ini`, style packages such as Microsoft or Google + project vocabulary) |
| Links | lychee (`lycheeverse/lychee-action` pinned by SHA in CI) |
| OpenAPI lint | Redocly CLI (`redocly lint`) or Spectral |
| Diagrams | Mermaid (rendered natively by GitHub and doc sites); Structurizr DSL or Mermaid C4 for C4 |
| Local hooks | lefthook or pre-commit (versioned config, not `.git/hooks`) |
| Site build | Starlight / Docusaurus build in CI; fail on broken links and build warnings |

## README standard

- Sections in order: name + one-line purpose, status badges (CI, version, license), quick start
  (copy-paste commands that work on a clean machine), usage example, configuration, links to
  docs/API reference, contributing, license.
- Commands are tested (CI job runs the quick start, or it is covered by an e2e test).
- No secrets, internal hostnames, or personal data in examples; use `example.com` and placeholders.

## CHANGELOG

- `## [Unreleased]` at the top; releases as `## [1.4.0] - 2026-09-27` (ISO 8601), newest first.
- Group entries under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security` only.
- Write for users: what changed and what they must do. Link issues/PRs and CVE IDs.
- Conventional commits may seed release notes (release-please, changesets), but a human edits the
  result.

## ADRs

- One decision per file, numbered, immutable once accepted; supersede with a new ADR and update the
  old one's status (`superseded by ADR-0012`).
- Minimum sections (MADR minimal): context and problem, decision drivers, considered options,
  decision outcome, consequences.
- Write an ADR for anything hard to reverse: data stores, frameworks, public API shape, auth model,
  deployment topology.

## Doc comments

- Every exported/public symbol has a doc comment stating purpose, parameters, return value, errors
  thrown/returned, and at least one example for non-trivial APIs.
- Examples compile and run: doctests (Python, Rust), `Example_` functions (Go), `{@snippet}`
  (Java 18+), `@sample` (Kotlin), TSDoc examples type-checked via extracted snippets.
- Examples follow repo rules: logger rather than `console.log`/`print`, no secrets, typed errors.

## OpenAPI documentation

- Every operation: `operationId` (camelCase verb+noun), `summary`, `description`, `tags`,
  `security`, and responses for every documented status.
- Errors: `application/problem+json` (RFC 9457) via shared `components.responses` — see
  `api-rest-openapi` for the schema.
- Use `examples`: the Example Object map on media types/parameters, and the JSON Schema
  `examples` array inside schemas (the Schema Object `example` keyword is deprecated since 3.1).
- Lint in CI and render with Redoc/Scalar/Swagger UI from the committed spec.

## Diagrams

- Mermaid for inline diagrams: `flowchart LR|TD` (not the legacy `graph` keyword),
  `sequenceDiagram`, `erDiagram`, `stateDiagram-v2`, `classDiagram`.
- C4: Level 1 context and Level 2 container for every system; Level 3 only for complex services.
- Every diagram has a title, labeled edges, and lives as text next to the docs it explains — no
  binary draw.io/PNG sources without the editable source committed.

## Docs CI

1. markdownlint + Vale on changed Markdown (Vale warnings as PR annotations, errors fail).
2. lychee link check (offline mode on PRs for relative links; full external check nightly).
3. OpenAPI lint and breaking-change diff (`oasdiff`) against `main`.
4. Build the docs site and API reference; publish previews per PR.
5. Docs-impact check: PRs touching public APIs, config or CLI must update docs or state
   "no docs impact" in the PR template.

## Security

- Never paste real tokens, customer data, internal URLs, or stack traces with secrets into docs.
- Sanitize logs and screenshots; redact before committing.
- Pin third-party GitHub Actions (lychee, Vale, deploy actions) by full commit SHA.

## Observability

- Track docs build time, broken-link count, and search-with-no-results terms (site analytics) to
  find gaps; review quarterly.

## Testing

- Doctests and example files run in the normal test suite.
- Quick-start commands executed in CI on a clean runner.
- Snapshot the generated OpenAPI document; a diff in PR review is expected and must be intentional.

## References

- `reference/code-comments.md` — Read when writing doc comments in TS, Python, Java, Kotlin, Go,
  C#, Swift, or Dart, or configuring their generators.
- `reference/openapi.md` — Read when documenting HTTP endpoints or reusable OpenAPI components.
- `reference/templates.md` — Read when creating a README, CHANGELOG, or ADR from scratch.
- `reference/docs-ci.md` — Read when setting up hooks, Vale, lychee, or the docs pipeline.

_Versions verified September 2026._
