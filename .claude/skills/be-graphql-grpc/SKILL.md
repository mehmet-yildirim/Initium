---
name: be-graphql-grpc
description: API contract standards for GraphQL and gRPC — schema-first design, GraphQL N+1 prevention with DataLoader, query depth/complexity limits, persisted operations, pagination and error models; Protobuf evolution rules, buf lint and breaking-change checks, deadlines, status codes, and streaming. Use when designing, implementing, or reviewing GraphQL schemas and resolvers or gRPC services and .proto files.
paths:
  - "**/*.graphql"
  - "**/*.gql"
  - "**/schema.graphqls"
  - "**/*.resolver.*"
  - "**/resolvers/**"
  - "**/*.proto"
  - "**/buf.yaml"
  - "**/buf.gen.yaml"
---

# GraphQL & gRPC Standards

## Choosing a protocol

- GraphQL: client-driven reads across many entities (web and mobile frontends, BFFs).
- gRPC: service-to-service calls, streaming, strict contracts, and performance-sensitive paths.
- REST/OpenAPI remains the default for public, cacheable, resource-oriented APIs.

## GraphQL

### Schema design
- Schema-first (or code-first generating a committed schema file); the schema is reviewed like code.
- Name by domain, not by database tables. Use `ID!` for identifiers, custom scalars for
  `DateTime`, `Email`, `URL`.
- Mutations take a single `input` object and return a payload type containing the result and
  typed user errors (`errors: [UserError!]!`) for expected business failures.
- Relay-style cursor pagination (`first`/`after`, `edges`, `pageInfo`) for every list that can grow.
- Deprecate with `@deprecated(reason:)`; remove only after usage telemetry shows zero traffic.

### Performance and safety
- Batch and cache per request with DataLoader (or equivalent) — never query inside a field
  resolver per parent item.
- Enforce maximum query depth, complexity/cost limits, and request timeouts.
- Production clients use persisted/trusted operations; disable arbitrary queries and
  introspection for public production endpoints when possible.
- Authorize in the domain/service layer per field or object, not only at the gateway.
- Never expose internal exception messages in `errors`; map to stable error codes in `extensions`.

## gRPC

### Protobuf rules
- `buf` for linting, formatting, code generation, and `buf breaking` against the main branch in CI.
- Package names are versioned (`acme.orders.v1`); one service per file; request/response
  messages are unique per RPC (`GetOrderRequest`/`GetOrderResponse`).
- Never change a field number or type; delete fields by marking them `reserved` (number and name).
- Every enum has a zero value `*_UNSPECIFIED`.
- Use well-known types (`google.protobuf.Timestamp`, `Duration`, `FieldMask`) instead of custom ones.

### Runtime
- Clients always set deadlines; servers propagate the remaining deadline downstream.
- Return canonical status codes (`INVALID_ARGUMENT`, `NOT_FOUND`, `FAILED_PRECONDITION`,
  `UNAVAILABLE`, …) with rich error details, never `UNKNOWN` for expected failures.
- Retries only for idempotent methods and retryable codes, configured via service config.
- Streaming RPCs handle cancellation and apply flow control; bound message sizes.
- Health checking (`grpc.health.v1`) and reflection only in non-production environments.
- mTLS between services; authentication metadata validated in interceptors.

## Testing

- GraphQL: operation-level integration tests against the real schema; snapshot the schema and fail
  CI on unreviewed breaking changes.
- gRPC: in-process server tests with generated clients; `buf breaking` as a contract test.
