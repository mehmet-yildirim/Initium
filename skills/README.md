# Skills Index

This directory documents all available AI coding skills for this project.
Skills are language-, framework-, and domain-specific rule sets that give AI tools
deep context only when a task needs it.

Every skill is a folder in `.claude/skills/<name>/` containing a `SKILL.md` in the
[Agent Skills](https://agentskills.io) open format. That folder is the **single source**;
nothing else needs to be edited by hand.

## How Skills Work

Only each skill's `name` and `description` sit in the agent's context. The body is loaded
when the task matches the description, or when a file matching the optional `paths`
globs is involved (progressive disclosure — no token cost for unused skills).

| Tool | How skills activate |
|------|-------------------|
| **Claude Code** | Native — reads `.claude/skills/`; also invocable as `/<skill-name>` |
| **Cursor** | Native — reads `.claude/skills/` (also `.agents/skills/`, `.cursor/skills/`) |
| **OpenCode** | Native — reads `.claude/skills/` via its `skill` tool |
| **Codex / Copilot / Gemini CLI** | Via `AGENTS.md`, which points agents to `.claude/skills/<name>/SKILL.md` |
| **Continue** | Generated rules in `.continue/rules/skills/*.md`, activated in `.continue/config.yaml` |

> Do not copy skills into `.agents/skills/` as well — Cursor and OpenCode read both
> locations and would load every skill twice.

## Available Skills

Every stack skill follows the same structure (baseline versions, toolchain, structure, errors,
security, observability, testing) and ends with the month its versions were verified. Long
recipes live in `reference/*.md` next to `SKILL.md` and load only when needed. Each file glob
belongs to exactly one skill.

### Languages

| Skill | Key Coverage |
|-------|-------------|
| `lang-java` | Java 25 LTS, Spring Boot 4, Jackson 3, JSpecify + NullAway, hexagonal packages, JUnit 6, Testcontainers |
| `lang-dotnet` | .NET 10 LTS, C# 14, minimal APIs with `TypedResults`, built-in OpenAPI and validation, xUnit v3, CPM, NuGetAudit |
| `lang-python` | Python 3.14, uv, ruff (incl. security rules), pip-audit, FastAPI feature folders, structlog, OpenTelemetry |
| `lang-typescript` | TypeScript 7 native compiler, `nodenext`, Node 24 type stripping, `erasableSyntaxOnly`, pino, typed errors |
| `lang-go` | Go 1.27, golangci-lint v2, `net/http` routing patterns, `slog`, govulncheck, synctest, fuzzing |
| `lang-rust` | Edition 2024, MSRV, Tokio, Axum, sqlx, thiserror/anyhow, tracing, nextest, cargo-deny |
| `lang-kotlin` | Backend Kotlin 2.4: Ktor 3.6, Spring Boot 4, coroutines, Exposed/jOOQ, Kotest/MockK |
| `lang-php` | PHP 8.4+, Laravel 13, PHPStan, Pint, Pest arch presets, Rector, composer audit |
| `lang-ruby` | Ruby 4.0 / 3.4, Rails 8, RuboCop/Standard, Sorbet or RBS, Brakeman, bundler-audit, Solid Queue |
| `lang-scala` | Scala 3.9 LTS, sbt 2 / Mill, scalafmt, scalafix, Cats Effect or ZIO, tapir, munit, otel4s |
| `lang-c` | C17 (opt-in C23), strict warnings, clang-tidy, cppcheck, sanitizers, fuzzing, `_FORTIFY_SOURCE=3` hardening, MISRA C:2025 |
| `lang-cpp` | C++23 (C++26 status), CMake 4 presets, Conan 2 / vcpkg, RAII, `std::expected`, lifetime pitfalls, library hardening modes |

### Backend & APIs

| Skill | Key Coverage |
|-------|-------------|
| `api-rest-openapi` | Resource design, OpenAPI 3.1 (3.2 status), RFC 9457 errors, cursor pagination, idempotency keys, ETags, versioning and deprecation, OWASP API Top 10 |
| `be-microservices` | Service boundaries, resilience (timeouts, retries, circuit breakers), SLOs, contract tests, secrets, Gateway API |
| `be-node` | Node 24 LTS, NestJS 12, Fastify 5, Hono 4, Zod 4, pino, OpenTelemetry, SSRF guard, graceful shutdown |
| `be-messaging` | Kafka 4 (KRaft, share groups), RabbitMQ, SQS, NATS, AsyncAPI 3, outbox, idempotent consumers, DLQs |
| `be-graphql-grpc` | GraphQL DataLoader, complexity limits, persisted queries, Federation v2; protobuf, buf v2, Connect, deadlines, health |
| `db-migrations` | Expand/contract, lock and statement timeouts, `CONCURRENTLY`, batched backfills, migration linters; per-tool references (Flyway, Liquibase, Alembic, Prisma 7, Drizzle, EF Core, Go tools, mobile) |

### AI / LLM Applications

| Skill | Key Coverage |
|-------|-------------|
| `ai-llm-apps` | Provider ports, structured output, OWASP LLM Top 10 (2026), RAG, cost and caching, GenAI telemetry, evals, MCP servers (2026-07-28 spec, OAuth) |

Pair with `/eval` to build evaluation suites for LLM features.

### Frontend Frameworks

| Skill | Key Coverage |
|-------|-------------|
| `fe-react` | React 19.3, React Compiler, Actions and `useActionState`, error boundaries, TanStack Query, Testing Library |
| `fe-nextjs` | Next.js 16: `proxy.ts`, Cache Components (`'use cache'`), async request APIs, secure Server Actions, CSP nonces |
| `fe-vue` | Vue 3.5 (3.6 Vapor status), Nuxt 4, Pinia, Vue Router 5 typed routes, `defineModel` |
| `fe-angular` | Angular 22: zoneless, signal inputs, Signal Forms, `resource()`/`httpResource()`, incremental hydration, Vitest |
| `fe-svelte` | Svelte 5 runes, SvelteKit 2 (3 RC status), load functions, form actions, hooks, CSP, adapters |

### Mobile Platforms

| Skill | Key Coverage |
|-------|-------------|
| `mobile-ios` | Xcode 27, Swift 6.4, Approachable Concurrency, `@Observable`, SwiftData, Swift Testing, privacy manifests, Keychain, APNs |
| `mobile-android` | Kotlin 2.4, AGP 9, Compose BOM, Navigation 3, KSP, Keystore + Tink, targetSdk 36, edge-to-edge, 16 KB pages |
| `mobile-kmp` | KMP shared logic, AGP 9 KMP plugin, Ktor, SQLDelight 2 or Room 3, Koin/Metro, Compose Multiplatform 1.12, SKIE vs Swift Export |
| `mobile-flutter` | Flutter 3.47 / Dart 3.13, Riverpod 3, GoRouter, real flavors, drift, accessibility, l10n |
| `mobile-reactnative` | Expo SDK 57 / RN 0.86, New Architecture, Hermes V1, expo-router, expo-secure-store, EAS Build/Update |

### UI & Visual Design

| Skill | Key Coverage |
|-------|-------------|
| `frontend-design` | *Vendored from Anthropic (Apache-2.0).* Distinctive, intentional web visual design: brief grounding, typography, AI-default clusters to avoid, token plan → build → screenshot critique |
| `impeccable` | *Vendored from Paul Bakaus (Apache-2.0).* Full design workflow with 23 subcommands (`/impeccable shape`, `critique`, `audit`, `polish`, `typeset`, `layout`, …), craft floor and bans, iOS/Android references |
| `design-apple-hig` | Apple HIG summary with links: Liquid Glass (incl. the iOS 27 transparency setting), layout and safe areas, navigation, Dynamic Type, SF Symbols, 44 pt targets |
| `design-material3` | Material 3 Expressive (CC BY 4.0, adapted): color roles, dynamic color, type scale, spring motion, 48 dp targets, large-screen rules, edge-to-edge, predictive back |
| `design-tokens` | Primitive / semantic / component tokens, `DESIGN.md` (Google DESIGN.md format), CSS / Tailwind / SwiftUI / Compose mapping |
| `accessibility` | WCAG 2.2 AA, European Accessibility Act, semantic HTML and ARIA, keyboard and focus, contrast, touch targets, screen-reader and automated testing |

Pair with `/design`, `/design-review`, `/polish`, `/design-system`, and `/a11y`. Vendored skills
are refreshed with `bash .initium/scripts/vendor-design-skills.sh`; see `THIRD_PARTY_NOTICES.md`.
Impeccable's optional detector, design hook, and live mode need `npx impeccable install`.

### Security

| Skill | Key Coverage |
|-------|-------------|
| `security-sast` | OWASP Top 10:2025 mapping, universal secure-coding rules, Semgrep/CodeQL/gitleaks/osv-scanner; per-language references |
| `security-supply-chain` | SBOMs (Syft, CycloneDX/SPDX), Sigstore signing, SLSA provenance and GitHub attestations, SHA pinning, release-age gates, trusted publishing, Scorecard |

> **Recommendation:** Keep `security-sast` and `security-supply-chain` active for all production
> projects alongside your language skill.

### Testing

| Skill | Key Coverage |
|-------|-------------|
| `testing-e2e` | Test pyramid, Playwright (fixtures, auth state, sharding, traces), Vitest browser mode, Pact contract tests, Testcontainers, flake policy |

### Infrastructure, DevOps & Operations

| Skill | Key Coverage |
|-------|-------------|
| `devops-docker` | BuildKit, multi-stage builds, secret/cache mounts, `buildx bake`, SBOM + provenance, hardened images, Compose watch and secrets |
| `devops-cicd` | GitHub Actions pinned by SHA, least-privilege `permissions`, OIDC, artifact attestations, zizmor/actionlint, environments |
| `devops-terraform` | Terraform 1.16 / OpenTofu 1.12, remote state, ephemeral resources and write-only arguments, tests with `mock_provider`, Infracost |
| `devops-observability` | OpenTelemetry, Collector hardening, pinned semantic conventions, exponential histograms, SLOs and burn-rate alerts, cost |
| `devops-kubernetes` | Kubernetes 1.35–1.37, Gateway API, Pod Security Standards, RBAC, NetworkPolicy, Helm 4 / Kustomize, Argo CD / Flux, admission policies |
| `devops-aws` | ECS Fargate (render → deploy by digest), EKS, Aurora, CloudFront + OAC, GitHub OIDC, Organizations/SCPs, AWS Backup |
| `devops-gcp` | Cloud Run (GPUs, Jobs, Direct VPC egress), GKE Autopilot, Cloud SQL editions, Workload Identity Federation, Cloud Build/Deploy |
| `devops-azure` | Container Apps, AKS, PostgreSQL Flexible Server, Key Vault + managed identity, GitHub federated credentials, azurerm vs Bicep |
| `devops-onprem` | k3s, Traefik + Gateway API, cert-manager, OpenBao/External Secrets, Grafana Alloy, CloudNativePG, Ansible, GitOps |

### Documentation

| Skill | Key Coverage |
|-------|-------------|
| `docs-generation` | Diátaxis, API docs from OpenAPI, ADRs, Mermaid, Keep a Changelog, Starlight/Docusaurus, Vale and lychee in CI |

## Activating Skills in Continue

Continue does not support the Agent Skills format, so `node .initium/scripts/sync-skills.mjs`
generates one rule per skill in `.continue/rules/skills/<name>.md`. Uncomment the ones your
project needs in `.continue/config.yaml`:

```yaml
rules:
  - .continue/rules/01-coding-standards.md
  # ...
  # - .continue/rules/skills/lang-go.md
  # - .continue/rules/skills/security-sast.md
```

## Adding or Changing Skills

Use `/skill new <topic>` — it gathers conventions from the codebase and writes the file for you.
To do it by hand:

1. Create `.claude/skills/<name>/SKILL.md`:
   ```markdown
   ---
   name: lang-example
   description: Example language standards — key frameworks and tools. Use when writing or reviewing Example code.
   paths:
     - "**/*.ext"
   ---

   # Example Language Standards

   ## Code Style
   ...
   ```
   - `name`: lowercase letters, digits, and single hyphens; max 64 characters; must equal the folder name.
   - `description`: 1–1024 characters; say what the skill covers **and when to use it**.
   - `paths`: optional globs; omit for task-triggered skills.
2. Run `node .initium/scripts/sync-skills.mjs` to validate and regenerate the Continue rule.
3. Add the skill to this index.

Skills shipped by Initium are overwritten by `/sync-initium`. Put project-specific knowledge in
a separate `project-<topic>` skill.
