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

### Languages

| Skill | Key Coverage |
|-------|-------------|
| `lang-java` | Spring Boot, JPA, JUnit 5, Java 21 |
| `lang-dotnet` | ASP.NET Core, EF Core, xUnit, C# 12 |
| `lang-python` | FastAPI, SQLAlchemy, pytest, type hints |
| `lang-typescript` | Strict TS, ESM, Bun/Node.js |
| `lang-go` | Idiomatic Go, stdlib, concurrency |
| `lang-rust` | Edition 2024, Tokio, Axum, sqlx, thiserror/anyhow, tracing, nextest, cargo-deny |
| `lang-kotlin` | Backend Kotlin: Ktor 3, Spring Boot, coroutines, Exposed/jOOQ, Kotest/MockK |
| `lang-php` | PHP 8.3+, Laravel 11+, PHPStan level 8+, Pint, Pest |

### Backend & APIs

| Skill | Key Coverage |
|-------|-------------|
| `be-microservices` | Service design, communication, observability |
| `be-node` | NestJS, Fastify, Hono, Zod validation, pino, OpenTelemetry, graceful shutdown |
| `be-messaging` | Kafka/RabbitMQ/SQS/NATS, event schemas, outbox, idempotent consumers, DLQs |
| `be-graphql-grpc` | GraphQL DataLoader, complexity limits, persisted queries; protobuf, `buf breaking`, deadlines |
| `db-migrations` | Flyway, Liquibase, Alembic, Prisma, Drizzle, Goose, Atlas, EF Core, Room, drift, SQLDelight |

### AI / LLM Applications

| Skill | Key Coverage |
|-------|-------------|
| `ai-llm-apps` | Provider ports, structured output, OWASP LLM Top 10, RAG, cost and caching, GenAI telemetry, evals, MCP servers |

Pair with `/eval` to build evaluation suites for LLM features.

### Frontend Frameworks

| Skill | Key Coverage |
|-------|-------------|
| `fe-react` | Hooks, React Query, RTL, forms |
| `fe-nextjs` | App Router, Server Components, Server Actions |
| `fe-vue` | Composition API, Pinia, Vue Router |
| `fe-angular` | Standalone, Signals, NgRx, RxJS |

### Mobile Platforms

| Skill | Key Coverage |
|-------|-------------|
| `mobile-ios` | Swift, SwiftUI, MVVM, async/await, SwiftData, Swift Testing |
| `mobile-android` | Kotlin, Jetpack Compose, Hilt, Room, Coroutines + Flow, Material 3 |
| `mobile-kmp` | KMP shared logic, Ktor, SQLDelight, Koin, Compose Multiplatform, SKIE |
| `mobile-flutter` | Dart 3, Riverpod, GoRouter, Freezed, drift |
| `mobile-reactnative` | Expo, TypeScript strict, React Navigation, Zustand, TanStack Query, EAS |

### Security

| Skill | Key Coverage |
|-------|-------------|
| `security-sast` | OWASP Top 10 patterns per language, injection, crypto, path traversal, secret detection, mobile storage |

> **Recommendation:** Keep `security-sast` active for all production projects alongside your language skill.

### Infrastructure, DevOps & Operations

| Skill | Key Coverage |
|-------|-------------|
| `devops-docker` | Dockerfile, Compose, security, optimization |
| `devops-cicd` | GitHub Actions, quality gates, deployment strategies |
| `devops-terraform` | Terraform / OpenTofu layout, remote state, `moved`/`import` blocks, plan/apply in CI, policy-as-code |
| `devops-observability` | OpenTelemetry, OTLP Collector, semantic conventions, SLOs and burn-rate alerts |
| `devops-aws` | ECS Fargate, EKS, RDS, S3/CloudFront, OIDC/IAM, Secrets Manager, CloudWatch |
| `devops-gcp` | Cloud Run, GKE Autopilot, Cloud SQL, Workload Identity Federation, Secret Manager |
| `devops-onprem` | k3s/kubeadm, MetalLB, Nginx Ingress, cert-manager, Vault, Harbor, Ansible, Velero |

### Documentation

| Skill | Key Coverage |
|-------|-------------|
| `docs-generation` | API docs, architecture docs, diagrams, changelogs |

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
