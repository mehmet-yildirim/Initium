---
name: be-node
description: Node.js backend standards — NestJS, Fastify, and Hono services on an active LTS runtime, schema validation with Zod, layered/hexagonal structure, pino logging, OpenTelemetry, graceful shutdown, and Vitest/Supertest testing. Use when writing or reviewing HTTP APIs, workers, or services running on Node.js, Bun, or edge runtimes.
globs:
  - "**/*.controller.ts"
  - "**/*.module.ts"
  - "**/*.service.ts"
  - "**/routes/**/*.ts"
  - "**/server.ts"
  - "**/app.ts"
  - "**/main.ts"
  - "**/nest-cli.json"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Node.js Backend Standards

Language-level rules are in `lang-typescript`; this skill covers service structure and runtime.

## Framework choice

| Framework | Use when |
|-----------|----------|
| NestJS | Large teams and domains that benefit from modules, DI, and strong conventions |
| Fastify | Performance-sensitive APIs that want a small core and plugin encapsulation |
| Hono | Edge/serverless or multi-runtime (Node, Bun, Deno, Workers) targets |

Pick one per service; do not mix frameworks inside a service.

## Structure

- Feature folders (`src/orders/`) containing route/controller, service (use cases), repository
  (port + adapter), and schemas. Controllers never touch the database directly.
- Composition root wires adapters to ports at startup; business code imports interfaces only.
- Configuration is parsed and validated once at startup (Zod schema over `process.env`); the
  process exits on invalid config.

## Validation and contracts

- Validate every request body, query, params, and headers at the edge with a schema
  (Zod/TypeBox/class-validator) and infer TypeScript types from it.
- Generate the OpenAPI document from the same schemas (`@nestjs/swagger`, `@fastify/swagger`,
  `@hono/zod-openapi`) so docs cannot drift.
- Consistent error envelope `{ error: { code, message, details } }` from one error handler; never
  leak stack traces in production.

## Runtime behavior

- Never block the event loop: offload CPU-heavy work to worker threads or a queue.
- Every outbound HTTP/DB call has a timeout and bounded retries with jitter; use `AbortSignal`.
- Graceful shutdown on SIGTERM/SIGINT: stop accepting, drain in-flight requests, close pools.
- Health endpoints: `/health/live` (process up) and `/health/ready` (dependencies reachable).
- Handle `unhandledRejection` by logging and exiting — a supervisor restarts the process.

## Security

- `helmet` (or equivalent headers), strict CORS allowlist, request body size limits.
- Rate limiting on auth and expensive endpoints (`@fastify/rate-limit`, `@nestjs/throttler`).
- Authorization in the service layer, not only in route guards.
- `npm audit` / `pnpm audit` in CI; lockfile committed; `npm ci` in builds.

## Observability

- Structured JSON logs with pino; include request id and trace id; redact auth headers and PII.
- OpenTelemetry auto-instrumentation loaded before the app (`--import` hook) with OTLP export.

## Testing

- Vitest (or the runtime's test runner) for unit tests with ports mocked.
- HTTP integration tests with Supertest / `fastify.inject` / `app.request` against the real app.
- Databases and brokers via Testcontainers; no shared test databases.
