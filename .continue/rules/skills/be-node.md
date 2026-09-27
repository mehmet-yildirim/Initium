---
name: be-node
description: Node.js backend standards — Node 24 LTS (Node 26 LTS from Oct 2026), NestJS 12, Fastify 5 and Hono 4 services, Zod 4 validation at the edge, hexagonal structure, typed errors mapped to RFC 9457 problem details, jose JWT validation, idempotent POSTs, SSRF-safe outbound calls, pino 10 and OpenTelemetry, graceful shutdown, and Vitest 5/Testcontainers testing. Use when writing or reviewing Node.js HTTP APIs, controllers, routes, workers, or server bootstrap code.
globs:
  - "**/nest-cli.json"
  - "**/*.controller.ts"
  - "**/src/routes/**/*.ts"
  - "**/server.ts"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Node.js Backend Standards

Service structure and runtime for Node.js. Language rules are in `lang-typescript`; HTTP API
contract rules (resources, errors, pagination, versioning) are in `api-rest-openapi`; brokers are
in `be-messaging`; cross-service patterns are in `be-microservices`.

## Baseline (September 2026)

- Runtime: Node.js 24 (Active LTS until 2026-10-20, then Maintenance until 2028-04-30). Plan the
  move to Node 26, which enters Active LTS on 2026-10-28. Never deploy odd-numbered releases.
- Frameworks: NestJS 12 (ESM packages, Standard Schema validation; 11 is fine for existing apps),
  Fastify 5 (6 is alpha — do not adopt yet), Hono 4.
- Libraries: Zod 4, pino 10, jose 6, Vitest 5 (requires Node >= 22.12).
- Pin the runtime in `.nvmrc`/`package.json#engines` and the container base image; CI tests the
  same major that production runs.

## Toolchain

- Typecheck with `tsc --noEmit` in CI; lint with ESLint (typescript-eslint) or oxlint (the NestJS 12
  default for new projects); one formatter per repo.
- Native TypeScript: type stripping is stable (Node 24.12+) and on by default for erasable syntax
  only. Use it for scripts and tooling with `erasableSyntaxOnly` and `verbatimModuleSyntax` in
  `tsconfig.json`. NestJS apps still need a build step — decorators with metadata and constructor
  parameter properties are not erasable.
- `--env-file=.env` (stable since Node 24.10) is for local development only; production reads
  real environment variables injected from a secrets manager.
- Commit the lockfile; install with `npm ci` / `pnpm install --frozen-lockfile`; run
  `npm audit --audit-level=high` (or the pnpm equivalent) in CI.

## Framework choice

| Framework | Use when |
|-----------|----------|
| NestJS | Large teams and domains that benefit from modules, DI, and strong conventions |
| Fastify | Performance-sensitive APIs that want a small core and plugin encapsulation |
| Hono | Edge/serverless or multi-runtime (Node, Bun, Deno, Workers) targets |

Pick one per service; do not mix frameworks inside a service.

## Structure

- Feature folders (`src/orders/`) holding the route/controller, use cases, ports, adapters, and
  schemas. Controllers parse input, call one use case, and map the result — no SQL, no SDK calls.
- Domain and use cases import only ports (interfaces). Vendor SDKs (DB drivers, HTTP clients, cloud
  SDKs, brokers) live in adapters behind those ports.
- One composition root wires adapters to ports at startup.
- Parse and validate configuration once at startup with a Zod schema over `process.env`; exit
  non-zero on invalid config.

## Validation and contracts

- Validate body, query, params, and relevant headers at the edge with a schema (Zod 4, TypeBox, or
  Standard Schema in NestJS 12) and infer types from it. Reject unknown fields on writes.
- Generate the OpenAPI document from the same schemas (`@nestjs/swagger`, `@fastify/swagger`,
  `@hono/zod-openapi`) and lint it in CI (see `api-rest-openapi`).
- Validate responses from third-party APIs too (OWASP API10: unsafe consumption).

## Errors

- Use cases return typed results (`Result<T, E>` with a discriminated union of domain error codes)
  for expected failures; throw only for bugs and infrastructure faults.
- Map domain errors to HTTP in one error handler, as RFC 9457 `application/problem+json`
  (`type`, `title`, `status`, `detail`, `instance`, plus a stable `code`). Format rules are in
  `api-rest-openapi`.
- Never leak stack traces, SQL, or internal messages. Log the full error server-side with the
  request id; return the request id to the client.
- Handle `unhandledRejection` and `uncaughtException` by logging and exiting non-zero; the
  supervisor restarts the process.

Read `reference/errors-and-auth.md` when implementing the error handler or the JWT adapter.

## Runtime

- Never block the event loop: offload CPU-heavy work to worker threads or a queue.
- Every outbound HTTP/DB call has a timeout (`AbortSignal.timeout(ms)`) and bounded retries with
  jitter, only for idempotent operations. Cross-service resilience is in `be-microservices`.
- Graceful shutdown on SIGTERM/SIGINT: fail readiness, stop accepting, drain in-flight requests
  within a deadline shorter than the pod's termination grace period, close pools, then exit.
- Health endpoints, aligned with `be-microservices`:
  - `/health/live` — process responsive; never checks dependencies.
  - `/health/ready` — can serve traffic (pools connected, not shutting down).
  - `/health/startup` — initialization finished; backs the Kubernetes startup probe.

## Security

- `helmet` (or `@fastify/helmet`, Hono `secureHeaders`), strict CORS allowlist, body size limits.
- Rate limit auth and expensive endpoints (`@fastify/rate-limit`, `@nestjs/throttler`); return
  `429` with `Retry-After`.
- Authentication: verify JWTs with `jose` (`jwtVerify` + `createRemoteJWKSet`), always pinning
  `algorithms`, `issuer`, and `audience`. Never decode-without-verify; never accept `alg: none`.
- Authorization in the use-case layer, per object (BOLA): derive the caller from the verified
  token, never from a client-supplied user id.
- Idempotency: unsafe `POST`s that create resources or move money accept an `Idempotency-Key`
  header; store key + request fingerprint + response atomically and replay it on retry. Contract
  rules are in `api-rest-openapi`.
- SSRF: any user-influenced outbound URL passes an allowlist (scheme `https`, known hosts), then
  every resolved IP is checked against private, loopback, link-local, and metadata ranges
  (`node:net` `BlockList`). Disable redirects or re-validate each hop; back it with an egress
  network policy. Read `reference/ssrf-guard.md` before writing a URL fetcher or webhook sender.
- Queries are parameterized through the ORM/query builder; never interpolate input into SQL or
  shell commands.

## Observability

- Structured JSON logs with pino (`pino-http` or the framework integration); include request id
  and trace id; redact `authorization`, cookies, tokens, and PII via `redact` paths. No
  `console.log` in service code.
- Load OpenTelemetry before the app (`node --import ./otel.js dist/main.js`) with OTLP export;
  auto-instrument HTTP, DB, and broker clients; add spans around use cases.
- Metrics: RED per route (rate, errors, duration) plus event-loop delay and pool saturation.

## Testing

- Vitest 5 for unit tests with ports faked (in-memory adapters over mocks where possible).
- HTTP tests against the real app instance: `fastify.inject`, Hono `app.request`, or Supertest for
  NestJS/Express — cover validation errors, auth failures, and the problem+json shape.
- Databases and brokers via Testcontainers; no shared test databases.
- Authorization tests per role and per object ownership (another user's id returns `404`/`403`).

_Versions verified September 2026._
