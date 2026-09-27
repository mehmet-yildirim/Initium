---
name: be-graphql-grpc
description: API contract standards for GraphQL and gRPC — GraphQL September 2025 spec (@oneOf inputs), DataLoader batching, depth/cost limits, persisted operations, subscription authorization, Apollo Federation 2 composition, experimental @defer/@stream; Protobuf evolution with buf v2 config (lint, format, breaking), protovalidate, deadlines, status codes, streaming, grpc.health.v1, Connect/gRPC-Web for browsers, and OpenTelemetry RPC conventions. Use when designing, implementing, or reviewing GraphQL schemas, resolvers, subgraphs, gRPC services, or .proto files.
globs:
  - "**/*.proto"
  - "**/*.graphql"
  - "**/*.gql"
  - "**/buf.yaml"
  - "**/buf.gen.yaml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# GraphQL & gRPC Standards

Contract and runtime rules for GraphQL and gRPC/Connect. REST/OpenAPI is in `api-rest-openapi`;
cross-service resilience is in `be-microservices`; service internals are in `be-node` / `lang-*`.

## Baseline (September 2026)

- GraphQL specification, September 2025 edition (OneOf input objects, schema coordinates).
  GraphQL.js 17 is current.
- `@defer`/`@stream` (incremental delivery) are not in the spec: the RFC is at Stage 2 (Draft) and
  GraphQL.js 17 exposes them only as experimental APIs.
- Apollo Federation 2 (latest composition version 2.15, LTS); Federation 1 is legacy.
- Buf CLI with `version: v2` `buf.yaml`/`buf.gen.yaml` (migrate with `buf config migrate`).
- Connect RPC: Connect-ES 2 (`@connectrpc/connect`, `@connectrpc/connect-web`), connect-go.
- OpenTelemetry RPC semantic conventions are at Release Candidate: `rpc.system.name`
  (`grpc`, `connectrpc`), fully qualified `rpc.method`, `rpc.response.status_code`.

## Choosing a protocol

- REST/OpenAPI: default for public, cacheable, resource-oriented APIs.
- GraphQL: client-driven reads across many entities (web and mobile frontends, BFFs).
- gRPC: service-to-service calls, streaming, strict contracts, performance-sensitive paths.
- Connect (or gRPC-Web): when browsers or simple HTTP clients must call Protobuf services.

## GraphQL

### Schema design
- Schema-first, or code-first that generates a committed schema file; review the schema like code.
- Name by domain, not database tables. `ID!` for identifiers; custom scalars for `DateTime`,
  `Email`, `URL` with validation in the scalar.
- Mutations take a single `input` object and return a payload with the result and typed user
  errors (`errors: [UserError!]!`) for expected business failures.
- Use `@oneOf` input objects for mutually exclusive options instead of several nullable arguments
  (`input UserBy @oneOf { id: ID  email: String }`). All fields are nullable and exactly one must be
  set; turning a oneOf input into a regular input later is non-breaking, the reverse is breaking.
- Relay-style cursor pagination (`first`/`after`, `edges`, `pageInfo`) for every list that can grow;
  enforce a maximum `first`.
- Deprecate with `@deprecated(reason:)`; remove only after usage telemetry shows zero traffic.

### Performance and safety
- Batch and cache per request with DataLoader (or equivalent) — never query inside a field resolver
  per parent item.
- Enforce maximum depth, cost/complexity limits, alias and batch limits, and request timeouts.
- Production clients use persisted/trusted operations; reject arbitrary documents and disable
  introspection on public production endpoints.
- Authorize in the domain/service layer per object and field, not only at the gateway or router.
- Never expose internal exception messages in `errors`; map to stable codes in `extensions.code`.

### Subscriptions
- Authenticate at connection init (for example the `graphql-ws` `connection_init` payload) and
  reject unauthenticated sockets before any subscription starts.
- Authorize when subscribing and again for every event delivered (the user may lose access to
  that object mid-stream); close the connection when the token expires.
- Limit concurrent subscriptions per connection and per user; filter events server-side.

### Incremental delivery
- Use `@defer`/`@stream` only when server, gateway, and clients all implement the same draft
  response format; keep them off public contracts until the spec is accepted.

### Federation
- Subgraphs opt in with `extend schema @link(url: "https://specs.apollo.dev/federation/v2.x",
  import: [...])`, importing only the directives they use; upgrade the router before raising a
  subgraph's federation version.
- Entities declare `@key`; fields resolvable by several subgraphs are explicitly `@shareable`.
- Run composition and schema checks in CI on every subgraph change (e.g. `rover subgraph check`)
  and publish only from the main branch.
- Subgraphs still authorize every field; the router is not a trust boundary for data access.

## gRPC

### Protobuf and buf
- `buf.yaml` v2 at the repository root; CI runs `buf lint`, `buf format --diff --exit-code`, and
  `buf breaking --against '.git#branch=main'`.

```yaml
version: v2
modules:
  - path: proto
deps:
  - buf.build/googleapis/googleapis
lint:
  use:
    - STANDARD
breaking:
  use:
    - FILE
```

- Versioned packages (`acme.orders.v1`); request/response messages unique per RPC
  (`GetOrderRequest`/`GetOrderResponse`).
- Never change a field number or type; delete fields by marking number and name `reserved`.
- Every enum has a zero value `*_UNSPECIFIED`.
- Use well-known types (`google.protobuf.Timestamp`, `Duration`, `FieldMask`) instead of custom ones.
- Declare validation rules in the schema with protovalidate and enforce them in a server
  interceptor, so every language validates the same way.

### Runtime
- Clients always set deadlines; servers propagate the remaining deadline downstream.
- Return canonical status codes (`INVALID_ARGUMENT`, `NOT_FOUND`, `FAILED_PRECONDITION`,
  `UNAVAILABLE`, …) with rich error details; never `UNKNOWN` or `INTERNAL` for expected failures.
- Retries only for idempotent methods and retryable codes, configured via service config.
- Streaming RPCs handle cancellation and apply flow control; set max message sizes explicitly.
- Health checking (`grpc.health.v1`) is always on, in every environment — Kubernetes gRPC probes
  and load balancers depend on it. Server reflection is enabled only in non-production.
- Authentication metadata is validated in interceptors; authorization happens in the service layer.

### Browser and HTTP clients
- Serve Connect, gRPC, and gRPC-Web from the same handlers (connect-go, Connect-ES on Node) or put
  an Envoy gRPC-Web filter in front of plain gRPC servers.
- Browser clients use `createConnectTransport` or `createGrpcWebTransport` from
  `@connectrpc/connect-web`. Browsers support only unary and server-streaming calls — design
  browser-facing APIs without client or bidirectional streaming.

## Security

- mTLS between services; TLS for every external endpoint.
- Validate all inputs at the boundary (scalars, protovalidate) and bound list sizes.
- GraphQL: persisted operations, depth/cost limits, and no production introspection on public
  endpoints. gRPC: no reflection in production.
- Log authentication and authorization failures with request id and principal, never tokens.

## Observability

- gRPC/Connect: OpenTelemetry instrumentation following the RPC conventions (`rpc.system.name`,
  `rpc.method` such as `acme.orders.v1.OrderService/GetOrder`, `rpc.response.status_code`). While the
  conventions are Release Candidate, pin the instrumentation version and opt in with
  `OTEL_SEMCONV_STABILITY_OPT_IN=rpc` where supported.
- GraphQL: one span per operation named by operation name and type; resolver-level spans only when
  sampled. Never record full query text or variables as attributes (PII, cardinality).
- Metrics: latency and error rate per RPC method / GraphQL operation; DataLoader batch sizes; rejected
  operations (depth, cost, unpersisted).

## Testing

- GraphQL: operation-level integration tests against the real schema; snapshot the schema and fail
  CI on unreviewed breaking changes; test authorization per field for each role, including
  subscriptions.
- Federation: composition checks in CI; router-level smoke tests for key entity queries.
- gRPC: in-process server tests with generated clients; `buf breaking` as the contract test;
  test deadline propagation and status-code mapping for every error path.

_Versions verified September 2026._
