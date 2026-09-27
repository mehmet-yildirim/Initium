---
name: api-rest-openapi
description: REST API design and OpenAPI contract standards — resource modeling, OpenAPI 3.1 (3.2 only where the toolchain supports it), RFC 9457 problem details, cursor pagination, filtering and sorting, Idempotency-Key, versioning with Deprecation (RFC 9745) and Sunset (RFC 8594), ETags and conditional requests, 429/Retry-After and the draft RateLimit fields, schema validation, OWASP API Security Top 10 (2023), Redocly/Spectral linting, breaking-change checks, contract testing (Pact, Schemathesis), and code generation. Use when designing, reviewing, or documenting HTTP APIs or editing OpenAPI/Swagger files.
globs:
  - "**/openapi*.y*ml"
  - "**/openapi*.json"
  - "**/swagger*.y*ml"
  - "**/swagger*.json"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# REST API & OpenAPI Standards

Contract rules for HTTP APIs, independent of language. Implementation in Node is in `be-node`;
GraphQL/gRPC are in `be-graphql-grpc`; events are in `be-messaging`; cross-service concerns are in
`be-microservices`; consumer pact files are in `testing-e2e`.

## Baseline (September 2026)

- OpenAPI 3.1.x is the default: its Schema Object is JSON Schema 2020-12, so one schema serves
  docs, validation, and codegen. Swagger 2.0 and OpenAPI 3.0 are legacy — convert when touched.
- OpenAPI 3.2.0 (September 2025) is backward compatible and adds the `QUERY` method,
  `additionalOperations`, `itemSchema` for streaming (SSE, JSON Lines), `in: querystring`,
  hierarchical tags, and the OAuth device flow. Tooling is uneven: Redocly CLI v2 lints it fully,
  Schemathesis supports it, Spectral support is not yet released, and Hey API `openapi-ts` does not
  support it. Adopt 3.2 only when every tool in your pipeline does.
- Standards used below: HTTP semantics RFC 9110, problem details RFC 9457 (obsoletes RFC 7807),
  `Deprecation` RFC 9745, `Sunset` RFC 8594, `Link` RFC 8288, JSON Merge Patch RFC 7396.
- Drafts, not RFCs: the IETF `Idempotency-Key` draft expired in April 2026 (the header remains a
  widely used convention); the `RateLimit`/`RateLimit-Policy` fields (draft-ietf-httpapi-ratelimit-headers)
  are still in IESG review and their syntax has changed between revisions.
- OWASP API Security Top 10 — 2023 edition is current.

## Toolchain

- One source of truth per API: either spec-first (hand-written OpenAPI, generated server types) or
  code-first (spec generated from the same schemas that validate requests). Commit the resulting
  spec either way.
- Lint in CI with Redocly CLI (`redocly lint`) or Spectral (`spectral lint` with a repo ruleset);
  warnings fail the build for new APIs.
- Check breaking changes against the main branch spec in CI
  (`oasdiff breaking --fail-on ERR -- "$base" "$revision"`, supports 3.0–3.2); a breaking change
  without a new major version fails the build.
- Every `example` must validate against its schema (lint rules or a CI script).
- Generate clients and types from the spec (Hey API `openapi-ts`, `openapi-typescript`, Redocly
  `generate-client`, OpenAPI Generator for other languages); never hand-edit generated code.
- Pin all tools as dev dependencies; run the same versions locally and in CI.

Read `reference/openapi-template.md` when starting a new spec — 3.1 skeleton, shared components,
lint rulesets, and CI steps.

## Resource design

- Resources are plural nouns in kebab-case (`/purchase-orders/{orderId}`); nest at most one level
  (`/orders/{orderId}/lines`). Actions that are not CRUD become sub-resources
  (`POST /orders/{orderId}/cancellation`), not verbs in paths.
- One JSON field casing across the whole API (camelCase by default); `operationId` on every
  operation; tags per resource.
- Methods follow RFC 9110 semantics: `GET`/`HEAD` safe; `PUT`/`DELETE` idempotent; `POST`
  creates or triggers; `PATCH` uses `application/merge-patch+json` (or JSON Patch when ordered
  operations are needed).
- Status codes: `200` read/update, `201` + `Location` on create, `202` + status resource for async
  work, `204` for no body. Never `200` with an error payload.
- Identifiers are opaque strings (UUID/ULID), never sequential integers exposed to clients.
- Timestamps are RFC 3339 in UTC; money is integer minor units plus ISO 4217 `currency`; enums are
  documented and new values are announced as non-breaking only if clients were told to tolerate them.
- Separate read and write schemas (`OrderCreate`, `OrderUpdate`, `Order`) instead of relying on
  `readOnly`/`writeOnly` alone.

## Errors (RFC 9457)

- Every 4xx/5xx returns `application/problem+json` with `type` (URI to human docs, or
  `about:blank`), `title`, `status`, `detail`, and `instance`, plus extensions: stable `code`,
  `requestId`, and `errors[]` (`pointer` as a JSON Pointer into the request, `detail`) for
  validation failures.
- Define `Problem` once in `components/schemas` and reuse `components/responses` for common errors.
- Status mapping: `400` malformed syntax, `401` missing/invalid credentials (with
  `WWW-Authenticate`), `403` authenticated but not allowed, `404` not found *or* not visible to the
  caller (avoid existence leaks), `409` state conflict, `412` precondition failed, `415`, `422`
  semantic validation, `428` precondition required, `429` rate limited, `500`, `503` (with
  `Retry-After`).
- `detail` is written for the client; never include stack traces, SQL, hostnames, or internal ids.

## Pagination, filtering, sorting

- Cursor pagination for any collection that can grow: `?limit=&cursor=`; the cursor is opaque
  (encoded, and signed or validated server-side) and encodes a stable sort plus a unique
  tiebreaker (`createdAt,id`).
- Response shape: `{ "data": [...], "page": { "nextCursor": "…" | null } }`; optionally also a
  `Link: <…>; rel="next"` header. Default `limit` (e.g. 20) and enforced `maximum` (e.g. 100).
- Offset pagination only for small, bounded admin lists. Omit total counts unless cheap and needed.
- Filters are explicit, allowlisted query parameters (`?status=paid&createdAfter=…`), each with a
  schema; unknown parameters return `400`. Map filters to parameterized queries — never concatenate.
- Sorting: `?sort=-createdAt,id` against an allowlist of sortable fields.

## Idempotency

- `POST` (and non-idempotent `PATCH`) operations that create resources or have side effects accept
  an `Idempotency-Key` request header (client-generated UUID). Document it as a header parameter;
  make it required for payments and other money-moving operations.
- The server stores key + authenticated principal + a fingerprint of the request + the final
  response, for a documented window (e.g. 24 h), and replays the stored response on retry.
- Same key with a different payload → `422`; a request with the same key still in progress → `409`;
  missing key where required → `400`.

Read `reference/idempotency-and-concurrency.md` when implementing idempotency keys or ETags.

## Versioning and deprecation

- Major version in the path (`/v1`) — or in the media type, but one scheme per organization.
  Within a major version only additive, backward-compatible changes.
- Breaking changes include: removing or renaming fields, operations, or enum values; making an
  optional input required; tightening validation; changing types, formats, status codes, or
  auth requirements; changing pagination or error shapes.
- Deprecate before removal: mark `deprecated: true` in the spec, send
  `Deprecation: @<unix-seconds>` and, once a removal date exists, `Sunset: <HTTP-date>` (never
  earlier than the deprecation date), plus `Link: <https://docs…>; rel="deprecation"`.
- Track usage of deprecated operations per client and contact remaining consumers before sunset.

## Caching and concurrency

- Return a strong `ETag` on single-resource representations; honour `If-None-Match` with `304`.
- Require `If-Match` on `PUT`/`PATCH`/`DELETE` of resources edited concurrently: mismatched ETag →
  `412`, missing header → `428`.
- `Cache-Control: no-store` on responses with personal or sensitive data; explicit `max-age` and
  `Vary` on public cacheable responses.

## Rate limiting

- Every throttled response is `429` with `Retry-After` (RFC 9110) and a problem+json body.
- Advertising quotas via the draft `RateLimit-Policy` / `RateLimit` fields is optional; if used,
  pin to one draft revision in docs and treat it as subject to change. Do not invent new
  `X-RateLimit-*` variants.
- Expose rate-limit headers to browsers via `Access-Control-Expose-Headers`.

## Validation

- Validate every request (path, query, headers, body) against the schema at the edge before any
  business logic; reject with `400`/`422` problem details.
- Request bodies set `additionalProperties: false` (blocks mass assignment); every string has
  `maxLength`, every array `maxItems`, every number bounds, every free-text field a `format` or
  `pattern` where one exists.
- Validate responses in tests (and optionally in non-production runtimes) so the implementation
  cannot drift from the spec.

## Security (OWASP API Security Top 10, 2023)

| Risk | Required control |
|---|---|
| API1 Broken Object Level Authorization | Check ownership of every object id in the use-case layer; ids from the path are untrusted |
| API2 Broken Authentication | OAuth 2.x/OIDC bearer tokens validated for issuer, audience, expiry, algorithm; rate-limit auth endpoints |
| API3 Broken Object Property Level Authorization | Separate read/write schemas; allowlist writable fields; never return internal fields |
| API4 Unrestricted Resource Consumption | Max page sizes, body limits, timeouts, per-client rate limits and quotas |
| API5 Broken Function Level Authorization | Deny by default; explicit role/scope per operation (`security` + scopes in the spec) |
| API6 Unrestricted Access to Sensitive Business Flows | Abuse controls on flows such as signup, checkout, and OTP (velocity limits, bot detection) |
| API7 Server-Side Request Forgery | Allowlist and IP-range checks on any user-supplied URL (see `be-node`) |
| API8 Security Misconfiguration | HTTPS only, strict CORS allowlist, security headers, no verbose errors |
| API9 Improper Inventory Management | Every deployed route is in the spec; retire old versions; no undocumented debug endpoints |
| API10 Unsafe Consumption of APIs | Validate and bound responses from third-party APIs; timeouts; no blind redirects |

- Declare `securitySchemes` and a global `security` requirement; public operations opt out
  explicitly with `security: []`.
- No credentials, tokens, or PII in URLs or query strings.

## Observability

- Log one structured line per request: method, route template (`http.route`, not the raw path),
  status, duration, request id, client id — never bodies with PII or auth headers.
- OpenTelemetry HTTP server/client instrumentation (stable HTTP semantic conventions); metrics per
  route and status class.
- Return the request id in a response header and in problem details for support correlation.
- Dashboard deprecated-operation traffic per client.

## Testing

- CI: spec lint, example validation, breaking-change diff, and generated-client compile.
- Spec conformance: run Schemathesis (property-based, generated from the spec) against the running
  service in CI; fix every schema violation or 5xx it finds.
- Integration tests assert status codes, problem+json bodies, pagination edges (empty, last page,
  invalid cursor), `ETag`/`If-Match` flows, and idempotent replays.
- Consumer-driven contract tests with Pact for internal consumers; providers verify pacts before
  deploy.
- Authorization tests per role and per object ownership for every operation (API1/API5).

_Versions verified September 2026._
