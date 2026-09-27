---
name: be-microservices
description: Microservices architecture patterns — service design, communication, resilience, observability. Use when designing service boundaries, inter-service communication, resilience, or distributed observability.
paths:
  - "**/docker-compose*.yml"
  - "**/k8s/**"
  - "**/helm/**"
  - "**/proto/**"
  - "**/*.proto"
---

# Microservices Architecture Standards

## Service Design Principles

### Bounded Contexts
- Each service owns exactly one bounded context — aligned with business domain, not technical layer
- Services are independently deployable — zero shared libraries with business logic
- Services own their own data — no shared databases between services
- Service size: team can understand it fully; full CI cycle < 5 minutes

### API-First Design
- Define the API contract (OpenAPI / Protobuf) before implementing
- Versioning: URL path (`/v1/`) for REST; package version for Protobuf
- Backward compatible changes only — never break consumers without a new version
- Publish API contracts to a schema registry or shared repo

## Communication Patterns

### Synchronous (REST / gRPC)
- Use for: real-time queries, user-facing operations requiring immediate response
- REST: for external APIs and simple CRUD; JSON over HTTPS
- gRPC: for internal service-to-service calls with high performance or streaming
- Circuit breaker on all outbound synchronous calls (Resilience4j, Polly, `go-resilience`)
- Timeouts on all outbound calls — never wait indefinitely

### Asynchronous (Events / Messages)
- Use for: decoupling, eventual consistency, fan-out operations
- Domain Events: past tense, immutable — `OrderPlaced`, `UserActivated`
- At-least-once delivery assumed — consumers MUST be idempotent
- Dead-letter queue (DLQ) for every consumer — alert on DLQ accumulation
- Event schema registry: Avro or Protobuf with schema evolution rules

### API Gateway Pattern
- Single entry point for external clients; handles: auth, rate limiting, routing, SSL termination
- Internal services communicate directly (not via gateway)
- BFF (Backend for Frontend) for client-specific aggregation

## Resilience Patterns

### Required for all outbound calls
- **Timeouts**: set at connection and read level — never default (infinite)
- **Retry**: exponential backoff with jitter; max 3 retries; idempotent operations only
- **Circuit Breaker**: open circuit after N failures in T seconds; half-open probe
- **Bulkhead**: separate thread pools for different downstream services

### Health Checks
- `GET /health/live` — liveness: is the process running? (restart if fails)
- `GET /health/ready` — readiness: can it serve traffic? (remove from LB if fails)
- `GET /health/startup` — startup: has initialization completed?

## Data Management

### Database per Service
- Each service has its own database instance or schema — no shared databases
- Cross-service data: each service maintains a local projection of the data it needs (event-driven sync)
- Saga pattern for distributed transactions: choreography (events) or orchestration (saga orchestrator)

### Event Sourcing (when applicable)
- Events are the source of truth — state is derived by replaying events
- Events are append-only and immutable
- Snapshots to avoid replaying entire event stream

## Observability (Non-Negotiable)

### Three Pillars
- **Traces**: Distributed tracing with OpenTelemetry; propagate `traceparent` header across all calls
- **Metrics**: Prometheus-compatible metrics; expose `/metrics` endpoint
- **Logs**: Structured JSON logs; include `trace_id`, `span_id`, `service`, `environment`

### Required Metrics
- Request rate, error rate, latency (p50, p95, p99) — the RED method
- Queue depth, consumer lag — for async consumers
- DB connection pool usage, slow queries

### Alerting Thresholds
- Error rate > 1%: warning; > 5%: critical
- p99 latency > SLA threshold: warning
- DLQ depth > 0 for > 5 minutes: critical

## Service-to-Service Auth
- **mTLS** for service-to-service in production (Istio/Linkerd handles this)
- **JWT / OIDC** with service accounts for non-mesh environments
- Never trust caller identity based on IP or header alone
- Secrets via Kubernetes Secrets or Vault — never environment variable strings in manifests

## Deployment Patterns
- Each service has its own CI/CD pipeline
- Container: Docker image with distroless or minimal base; non-root user
- Orchestration: Kubernetes; Helm chart per service
- Deployment strategy: Rolling update for stateless; Blue-Green for stateful or critical
- Feature flags for risky deployments (decouple deploy from release)
- Canary releases for high-traffic services

## Local Development
- `docker-compose.yml` for running dependencies (DB, queue, other services)
- Service stubs / contract tests (Pact) so services can be developed independently
- Environment: `.env.local` with local service URLs
