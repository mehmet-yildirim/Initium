---
name: be-microservices
description: Distributed-system architecture standards — bounded contexts and database-per-service, API evolution and deprecation, sync vs async communication, resilience (timeouts, deadline propagation, retry budgets, circuit breakers via Resilience4j, Polly v8/Microsoft.Extensions.Http.Resilience, failsafe-go), aligned health probes, Kubernetes Gateway API, mTLS and External Secrets, OpenTelemetry with SLO burn-rate alerting, and Pact/Testcontainers testing. Use when designing service boundaries, inter-service communication, resilience, rollout, or distributed observability.
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Microservices Architecture Standards

Cross-service design. Related skills: `be-messaging` (events, outbox, consumers), `api-rest-openapi`
(HTTP contracts), `be-graphql-grpc` (gRPC/GraphQL contracts), `be-node` (service internals),
`devops-kubernetes`, `devops-observability`, `testing-e2e` (Pact files).

## Baseline (September 2026)

- Edge routing: Kubernetes Gateway API (v1.6 is current; HTTPRoute/GRPCRoute, and TCPRoute/UDPRoute
  are Standard). Do not start new work on Ingress-NGINX — it was retired in March 2026 and gets no
  security fixes; the Ingress API itself is feature-frozen.
- Resilience libraries: Resilience4j (JVM), Polly v8 via `Microsoft.Extensions.Http.Resilience` /
  `Microsoft.Extensions.Resilience` (.NET), `failsafe-go` or `sony/gobreaker/v2` (Go).
- Telemetry: OpenTelemetry SDKs with OTLP export and W3C Trace Context propagation.
- Secrets: External Secrets Operator (`external-secrets.io/v1` API) or Vault; never plain
  Kubernetes Secrets committed to Git.
- Contract testing: Pact specification v4 (`@pact-foundation/pact` 16.x for JS).

## Service design

- Start with a modular monolith; split out a service only when a bounded context needs
  independent deployment, scaling, or ownership.
- One service owns one bounded context and its data. No shared databases, no shared libraries
  containing business logic.
- A service is owned by one team, fits in one team's head, and its CI pipeline finishes in minutes.
- Inside each service follow hexagonal layering (domain → ports → adapters); vendor SDKs live in
  adapters only.

## API contracts and evolution

- Contract first: OpenAPI for REST (`api-rest-openapi`), Protobuf for gRPC (`be-graphql-grpc`),
  AsyncAPI for events (`be-messaging`). Contracts live in version control and are linted in CI.
- Only backward-compatible changes within a version; breaking changes get a new version that runs
  alongside the old one.
- Deprecation policy: announce with `Deprecation` (RFC 9745) and `Sunset` (RFC 8594) headers and a
  `Link: rel="deprecation"` to migration docs; keep the old version for at least one published
  support window; remove only after telemetry shows no traffic.
- `can-i-deploy` (Pact Broker/PactFlow) or schema-registry compatibility checks gate every deploy.

## Communication

- Synchronous (REST/gRPC) for queries and user-facing requests that need an immediate answer.
  gRPC for internal high-throughput or streaming calls; REST for external and simple CRUD.
- Asynchronous events for decoupling, fan-out, and eventual consistency. Follow `be-messaging`
  for event design, the transactional outbox, idempotent consumers, and DLQs — do not duplicate
  those rules here.
- Unsafe cross-service writes carry an idempotency key so callers can retry safely.
- Avoid synchronous call chains deeper than two hops on a user request; replace with events,
  local projections, or a BFF that fans out in parallel.
- External clients enter through an API gateway or BFF (authN, rate limits, routing, TLS);
  internal services call each other directly over the mesh, not through the public gateway.

## Resilience

Every outbound call has, at minimum:

- **Timeouts** on connect and on the whole request — never library defaults. Propagate the
  remaining deadline downstream (gRPC deadlines, a request-deadline header for HTTP).
- **Retries** only for idempotent operations or requests with an idempotency key; exponential
  backoff with full jitter; at most 3 attempts; retry at one layer only (client or mesh, not both).
- **Retry budgets**: cap retries to a fraction of live traffic (for example 10–20%) so retries
  cannot amplify an outage.
- **Circuit breakers** per downstream: open on failure ratio over a sliding window, half-open probes.
- **Bulkheads**: concurrency limits per downstream (semaphores or bounded pools) so one slow
  dependency cannot exhaust all workers.
- **Load shedding**: reject early with `503`/`RESOURCE_EXHAUSTED` and `Retry-After` when saturated.
- **Fallbacks** only when a degraded answer is correct for the business (cached read, default).

.NET `AddStandardResilienceHandler` retries every HTTP method by default — call
`options.Retry.DisableForUnsafeHttpMethods()` unless all unsafe calls carry idempotency keys.
Read `reference/resilience-and-probes.md` for configuration examples.

## Health checks and probes

Same endpoints in every service (matches `be-node`):

| Endpoint | Kubernetes probe | Checks | On failure |
|---|---|---|---|
| `/health/startup` | `startupProbe` | Initialization done (config, migrations verified, caches warm) | Keep waiting, then restart |
| `/health/live` | `livenessProbe` | Process responsive; never dependencies | Restart container |
| `/health/ready` | `readinessProbe` | Can serve now (pools up, not draining) | Remove from endpoints |

- Readiness never fails because a *downstream service* is down — that causes cascading removal.
  Check only the service's own required resources.
- On SIGTERM: fail readiness first, keep serving in-flight requests, then exit within
  `terminationGracePeriodSeconds`.

## Data management

- Database per service (instance or schema with separate credentials).
- Cross-service reads use local projections built from events, or an API call with caching.
- Distributed workflows use sagas — choreography for simple flows, an orchestrator (for example
  a workflow engine) when there are more than a few steps or compensations.
- Event sourcing only where an audit trail or temporal queries are core requirements; snapshot
  long streams.

## Security

- Zero trust between services: mTLS everywhere (service mesh such as Istio or Linkerd, or
  platform-issued workload certificates). Never trust caller identity from IP or an unsigned header.
- End-user identity propagates as a verified token (JWT/OIDC; exchange for a downscoped token per
  hop where supported). Each service authorizes on its own; the gateway is not the only check.
- Secrets come from External Secrets Operator or Vault into the pod at runtime; least-privilege
  credentials per service; rotate automatically.
- Default-deny NetworkPolicies; allow only declared service-to-service paths and egress.

## Observability

- Traces: OpenTelemetry on every inbound and outbound call and message; propagate `traceparent`
  across HTTP, gRPC, and broker headers.
- Metrics: RED per endpoint (rate, errors, duration histograms), saturation (pool usage, queue
  depth), and consumer lag for async consumers.
- Logs: structured JSON via a logger with `trace_id`, `span_id`, `service.name`, and environment;
  never secrets or PII.
- SLOs per user-facing journey (availability and latency). Alert on error-budget burn rate with
  multi-window, multi-burn-rate rules (page on fast burn, ticket on slow burn) — not on fixed
  error percentages. Alert thresholds are in `reference/resilience-and-probes.md`.
- DLQ and lag alerts follow `be-messaging`.

## Deployment

- One pipeline and one deployable artifact per service; immutable, signed images (see
  `devops-docker`, `devops-cicd`).
- Progressive delivery: canary or blue-green with automatic rollback on SLO regression.
- Feature flags decouple deploy from release; expand/contract for schema and contract changes.

## Testing

- Unit tests for domain and use cases with ports faked.
- Integration tests for adapters against real dependencies via Testcontainers (database, broker,
  cache) — no shared environments.
- Consumer-driven contract tests with Pact for every service-to-service HTTP or message
  interaction; providers verify pacts in CI and `can-i-deploy` gates releases.
- Component tests: run one service with its real database and stub its HTTP neighbours.
- Keep cross-service end-to-end tests to a few critical journeys (`testing-e2e`).
- Fault injection (latency, errors, dropped connections) in staging to prove timeouts, breakers,
  and fallbacks work.

## Local development

- Compose file for dependencies (database, broker, other services' stubs); see `devops-docker`.
- `.env.example` documents required variables with placeholder values; never commit real `.env`.

_Versions verified September 2026._
