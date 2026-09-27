# Documentation Agent — Architecture & Tool Guide

This document defines the documentation generation strategy for AI-native projects:
what to generate, which tools to use per stack, how to wire everything into CI/CD,
and how AI agents (including Initium's slash commands) fit into the workflow.

Detailed, versioned standards (Diátaxis layout, Keep a Changelog, ADRs, doc-comment idioms,
OpenAPI descriptions, docs CI) live in the
[`docs-generation` skill](../../../.claude/skills/docs-generation/SKILL.md); HTTP contract rules
live in [`api-rest-openapi`](../../../.claude/skills/api-rest-openapi/SKILL.md). This guide maps
those standards to the slash commands and pipeline.

---

## Documentation Matrix — Audience × Format

Every documentation artefact targets a specific audience. Define both before generating.

| Type | Audience | Format | Trigger | Tool | Command |
|------|----------|--------|---------|------|---------|
| API Reference | API consumers, integrators | OpenAPI 3.1 + Redoc / Scalar / Swagger UI | On spec change | SpringDoc, FastAPI built-in, tsoa, swaggo | `/doc-api` |
| Code docs | Developers reading/maintaining code | TSDoc/JSDoc, docstrings, GoDoc, KDoc | On PR | TypeDoc, Sphinx / mkdocstrings, Javadoc, Dokka, `dart doc`, DocC | `/docs` |
| Architecture | Developers, architects | Mermaid / C4 / PlantUML in Markdown | On design change | Mermaid, Structurizr DSL, PlantUML | `/doc-diagrams`, `/docs` |
| Developer guide | Onboarding developers | Markdown site | On feature complete | Starlight, Docusaurus 3, VitePress | `/doc-site` |
| Changelog | All developers, release managers | Markdown (Keep a Changelog) | On git tag | git-cliff, release-please (human-curated) | `/doc-changelog` |
| DB schema | Developers, DBAs | ERD + table descriptions | Post-migration | SchemaSpy, tbls, DBML | `/doc-schema` |
| SDK clients | Third-party developers | Language-idiomatic code | On OpenAPI change | Speakeasy, Hey API, openapi-generator | — |
| Stakeholder summary | Executives, product managers | Markdown → PDF | On release | AI-generated from technical docs | `/doc-changelog` (release summary), `/docs` (user-facing guide) |
| `llms.txt` | AI tools, LLMs | Plain text manifest | On deploy | Custom script | `/doc-site` |

---

## Tool Recommendations by Stack

### API Reference (OpenAPI 3.1)

| Stack | Tool | Config | Auto? |
|-------|------|--------|-------|
| **Java / Spring Boot** | `springdoc-openapi-starter-webmvc-ui` | Annotations: `@Operation`, `@Schema` | ✓ (zero-config) |
| **Kotlin / Spring** | Same as Java | Same | ✓ |
| **Python / FastAPI** | Built-in | Python type hints | ✓ (zero-config) |
| **Python / Django** | `drf-spectacular` | `@extend_schema` decorator | ✓ with decorators |
| **.NET / ASP.NET Core** | `Microsoft.AspNetCore.OpenApi` (built in since .NET 9) or `Swashbuckle.AspNetCore` | XML doc comments | ✓ |
| **TypeScript / Node** | `tsoa` (code-first) or `zod-to-openapi` | Decorators or Zod schemas | ✓ with setup |
| **TypeScript / NestJS** | `@nestjs/swagger` | Decorators: `@ApiProperty` | ✓ |
| **Go** | `swaggo/swag` | Comment annotations | ✓ with `swag init` |
| **iOS / Swift** | n/a — use REST spec | — | — |
| **Android / Kotlin** | n/a — consume spec | — | — |
| **Flutter / Dart** | n/a — consume spec | — | — |

**Output:** Always produce a single `openapi.json` / `openapi.yaml` at the repo root.
Multiple services: merge with `redocly join` or the Speakeasy merge command.
Generate the spec from code **or** treat it as the source of truth — never both.

### Code-Level Documentation

| Stack | Tool | Command | Output |
|-------|------|---------|--------|
| TypeScript/JS | TypeDoc 0.28 | `npx typedoc` | `docs/reference/api/` (HTML) |
| Python | Sphinx + `autodoc` (or mkdocstrings) | `sphinx-build -b html docs/source docs/build/html` | `docs/build/html/` |
| Java | `javadoc` (Maven plugin) | `mvn javadoc:javadoc` | `target/site/apidocs/` |
| Kotlin | Dokka 2 | `./gradlew :module:dokkaGenerate` | `build/dokka/html/` |
| .NET / C# | DocFX | `docfx build` | `_site/` |
| Go | `pkgsite` / go.dev | `go doc ./...` | Hosted at pkg.go.dev |
| Swift | DocC | `xcodebuild docbuild` or `swift package generate-documentation` | `.doccarchive` |
| Dart/Flutter | `dart doc` | `dart doc` | `doc/api/` |

Doc-comment conventions per language: `docs-generation` → `reference/code-comments.md`.

### Architecture Diagrams

**Mermaid** — recommended for all teams (renders natively on GitHub, Docusaurus, Starlight, GitLab).
Use `flowchart LR|TD` (not the legacy `graph` keyword), `sequenceDiagram`, `erDiagram`,
`stateDiagram-v2`:
```
Simple + widely supported + renders in markdown previews
```

**Structurizr DSL** — for teams needing formal C4 model:
```
C4-native, workspace.dsl → JSON / SVG / PNG
structurizr-cli export -workspace workspace.dsl -format svg
```

**PlantUML** — for complex UML sequences, state diagrams, class diagrams:
```
# Pin a release tag (and digest) instead of :latest
docker run --rm -v "$(pwd):/data" plantuml/plantuml:<version> -tsvg /data/diagrams/*.puml
```

### Documentation Sites

| Tool | Best for | Hosting | Key feature |
|------|---------|---------|------------|
| **Starlight** (Astro) | New docs sites of any size | Any static host | Fast, accessible defaults, built-in search, i18n |
| **Docusaurus 3** | Product/API docs with versioning | Vercel, Netlify, GitHub Pages | React MDX, built-in versioning, i18n |
| **VitePress** | Vue-heavy teams | Any static host | Fastest build, Vue components in docs |
| **Mintlify** | API-first products | Mintlify hosted | Zero-config, AI search built-in |
| **MkDocs Material** | Existing Python-heavy sites only | ReadTheDocs, self-hosted | In maintenance mode (critical fixes until May 2027) — do not start new sites on it; plan a migration |

### Changelog / Release Notes

**`git-cliff`** — recommended for all polyglot repos:
```bash
# Install
brew install git-cliff  # or: cargo install git-cliff

# Generate
git-cliff --output CHANGELOG.md

# Since last tag
git-cliff v1.0.0..HEAD --output CHANGELOG.md
```

Requires [conventional commits](https://www.conventionalcommits.org/) format.
Configure via `cliff.toml` at repo root. Generated output is a draft — a human curates it into
Keep a Changelog sections (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`).

**`release-please`** — if you want automated release PRs on GitHub:
```yaml
# .github/workflows/release-please.yml (step)
uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0
with:
  release-type: node  # or: python, rust, simple
```

### Database Schema Docs

**SchemaSpy** (best for auto-extraction from live DB):
```bash
# Pin a release tag (and digest) instead of :latest
docker run --rm -v "$(pwd)/docs/database:/output" schemaspy/schemaspy:<version> \
  -t pgsql -host localhost -port 5432 -db myapp -u postgres -p "$DB_PASS"
```

**DBML** (best for documentation-first approach):
```bash
npm install -g @dbml/cli
dbml2html schema.dbml -o docs/database/schema.html
```

**tbls** (Go binary, fastest, Markdown output):
```bash
tbls doc postgres://user:pass@localhost:5432/mydb docs/database/
```

### SDK Generation

**Speakeasy** — idiomatic SDKs in 6+ languages from your OpenAPI spec:
```bash
speakeasy generate sdk -s openapi.json
```
Produces: TypeScript, Python, Go, Java, C#, PHP — each language-idiomatic.

**Hey API** — TypeScript-only, lighter weight:
```bash
npx @hey-api/openapi-ts -i openapi.json -o src/generated -c axios
```
Produces: typed client + Zod schemas + TanStack Query hooks.

---

## CI/CD Documentation Pipeline

Add this workflow to `.github/workflows/docs.yml`. Actions are pinned by full commit SHA (the
comment records the version); let Dependabot or Renovate bump them. Lint, prose and link checks
for Markdown are in `docs-generation` → `reference/docs-ci.md` — add that `lint` job alongside
these.

```yaml
name: Documentation

on:
  push:
    branches: [main]
    paths: ['src/**', 'docs/**', 'openapi.*', 'CHANGELOG.md', 'cliff.toml']
  release:
    types: [published]

permissions: {}

jobs:
  # ── API Reference ──────────────────────────────────────────────────────────
  api-docs:
    name: Generate API Reference
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # TODO: uncomment for your stack
      # Spring Boot
      # - run: mvn springdoc-openapi-maven-plugin:generate -DskipTests

      # FastAPI (Python)
      # - run: |
      #     pip install -e ".[dev]"
      #     python -c "from app.main import app; import json; open('openapi.json','w').write(json.dumps(app.openapi()))"

      # TypeScript / tsoa
      # - run: npm ci && npm run openapi:generate

      # Go / swag (pin a release)
      # - run: go install github.com/swaggo/swag/cmd/swag@v1 && swag init

      - name: Validate OpenAPI spec
        run: npx --yes @redocly/cli lint openapi.json

      - name: Bundle for docs site
        run: npx --yes @redocly/cli bundle openapi.json -o docs/static/openapi-bundled.json

      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: openapi-spec
          path: openapi.json

  # ── Code Documentation ─────────────────────────────────────────────────────
  code-docs:
    name: Generate Code Docs
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # TypeScript
      # - run: npm ci && npm run docs:generate  # TypeDoc

      # Python
      # - run: pip install sphinx sphinx-rtd-theme && sphinx-build -b html docs/source docs/build/html

      # Java
      # - run: mvn javadoc:javadoc -DskipTests

      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: code-docs
          path: |
            docs/build/html/
            docs/reference/api/
            target/site/apidocs/
            doc/api/

  # ── Documentation Site ─────────────────────────────────────────────────────
  docs-site:
    name: Build Documentation Site
    runs-on: ubuntu-24.04
    needs: [api-docs, code-docs]
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          name: openapi-spec

      # TODO: uncomment for your generator (Starlight / Docusaurus / VitePress)
      # - run: cd docs-site && npm ci && npm run build

      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: docs-site
          path: docs-site/build/

  # ── Changelog draft ────────────────────────────────────────────────────────
  # Produces a draft for a human to curate; the curated CHANGELOG.md lands via a normal PR.
  changelog:
    name: Draft Changelog
    runs-on: ubuntu-24.04
    if: github.event_name == 'release'
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - run: npx --yes git-cliff@2 --latest --output CHANGELOG.draft.md
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: changelog-draft
          path: CHANGELOG.draft.md

  # ── Schema Docs ────────────────────────────────────────────────────────────
  schema-docs:
    name: Generate Schema Docs
    runs-on: ubuntu-24.04
    if: github.event_name == 'push'
    permissions:
      contents: read
    # services: postgres: ...  (add your DB service here)
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # - run: |
      #     docker run --rm -v "$(pwd)/docs/database:/output" \
      #       --network host schemaspy/schemaspy:<version> \
      #       -t pgsql -host localhost -db myapp -u postgres -p "$DB_PASS"
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: schema-docs
          path: docs/database/
```

---

## Documentation as Code — Principles

### 1. Docs live next to code
Source directories hold doc comments and, where a module needs local context, a short
`README.md` that links into `docs/`. Long-form docs go under `docs/`.
```
src/payments/
├── payment.service.ts      # source (doc comments on exported symbols)
├── payment.service.test.ts # tests
└── README.md               # module-level context (why, not what) → links into docs/
```

### 2. Every PR must update relevant docs
Add to your PR template checklist:
```
- [ ] Docs updated (README / docs/ / OpenAPI / CHANGELOG), or
- [ ] No docs impact — reason:
```

### 3. Docs staleness gate in CI
```bash
#!/usr/bin/env bash
# scripts/check-docs-staleness.sh
# Warn if a source file changed without a docs update in the same PR
CHANGED_SRC=$(git diff origin/main --name-only | grep "^src/" | grep -v "\.test\.")
CHANGED_DOCS=$(git diff origin/main --name-only | grep "^docs/")
if [ -n "$CHANGED_SRC" ] && [ -z "$CHANGED_DOCS" ]; then
  echo "WARNING: source code changed but no documentation was updated."
  echo "Consider running /docs <file> or /doc-api to update affected docs."
fi
```

### 4. llms.txt — Make docs AI-readable
Generate a [`llms.txt`](https://llmstxt.org/) file for AI tools consuming your docs
(`/doc-site` generates one as part of the site build):

```bash
# scripts/generate-llms-txt.sh
cat > llms.txt << 'EOF'
# <Project Name>

> <One-line description>

## API Reference
- [OpenAPI Spec](/openapi.json): Machine-readable API specification
- [API Docs](/docs/api): Human-readable reference

## Key Resources
- [Architecture](/docs/architecture/overview.md): System design
- [Getting Started](/docs/guides/onboarding.md): Developer setup guide
- [Domain Glossary](/docs/context/domain-glossary.md): Business terms
- [Changelog](/CHANGELOG.md): Release history

## Source
- [GitHub](https://github.com/org/repo)
EOF
```

Place `llms.txt` at your docs site root and repo root.

---

## Stakeholder Documentation Strategy

Produce multiple audiences from the same source using audience-specific views:

```
docs/
├── _audience/
│   ├── developers.md     → full technical detail
│   ├── architects.md     → patterns, decisions, trade-offs
│   └── executives.md     → business impact, timelines, KPIs
└── context/
    └── project-brief.md  → authoritative source of truth
```

### AI-generated stakeholder summary

There is no dedicated stakeholder command; two commands cover it:

- **`/doc-changelog <range>`** — Step 5 produces a non-technical release summary alongside the
  developer changelog: user-facing impact and business value per `feat:`, what was broken and
  its severity per `fix:`.
- **`/docs <feature or release>`** — ask for a *user-facing guide* aimed at executives or product
  managers. The agent reads architecture docs, CHANGELOG, and release notes, then produces:
  - Business impact summary
  - Feature highlights (non-technical)
  - Risk and mitigation summary
  - Timeline view

`/doc-site` can publish these pages in a stakeholder section of the docs site.

---

## AI Documentation — Best Practices

### What AI generates well
- Initial docstrings from function signatures (verified against tests)
- Non-technical summaries from technical architecture docs
- "Getting started" guides from working code examples
- FAQ sections from support history

### What AI must NOT generate alone
- Security or compliance documentation (requires human domain expertise)
- Deprecation notices (risk of incorrect signalling)
- SLA / contractual specifications
- Anything that states behavioral guarantees not validated by tests

### Validation pattern
```
AI generates → human reviews → test examples run in CI → merge
```

Never merge AI-generated docs that haven't been validated against actual behavior.

---

## Slash Command Reference

| Command | Purpose |
|---------|---------|
| `/docs <file, module, or feature>` | Doc comments (JSDoc/TSDoc, docstrings, GoDoc), an architecture document, or a user-facing guide — the type follows the request. `/loop` runs it on every new or changed file |
| `/doc-api [path \| service \| all]` | Detect stack → generate or update the OpenAPI spec → validate → enrich → Swagger UI / ReDoc output |
| `/doc-schema [live \| migrations \| prisma \| dbml \| <table>]` | Database schema documentation: Mermaid ERD, table reference, constraints, indexes |
| `/doc-diagrams [<endpoint> \| <flow> \| all] [--plantuml]` | Mermaid sequence diagrams traced from source into `docs/diagrams/` (optional PlantUML) |
| `/doc-site [docusaurus \| mkdocs \| vitepress \| rebuild]` | Scaffold or regenerate the documentation website, embed the OpenAPI spec and diagrams, generate `llms.txt` |
| `/doc-changelog [unreleased \| <from>..<to> \| --tag vX.Y.Z \| --since <date>]` | `CHANGELOG.md` from conventional commits via git-cliff, plus a stakeholder release summary and breaking-change check |
