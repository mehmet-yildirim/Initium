---
name: lang-go
description: Go standards — Go 1.27 (generic methods, stdlib uuid, encoding/json/v2) with 1.26 support, golangci-lint v2, govulncheck, go fix modernizers, hexagonal package layout, error wrapping with errors.AsType, context and errgroup concurrency, net/http ServeMux patterns, log/slog and OpenTelemetry, and testing with synctest, fuzzing, and testcontainers-go. Use when writing, reviewing, or configuring Go code, go.mod, or golangci-lint.
globs:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
  - "**/go.work"
  - "**/.golangci.y*ml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Go Standards

Idiomatic Go for services and libraries. Container and CI specifics live in `devops-docker` and
`devops-cicd`.

## Baseline

- Go 1.27 (released 2026-08-19). Support the two latest releases (1.26, 1.27) — older ones get no
  security fixes.
- Applications: `go 1.27` in `go.mod`. Libraries: `go` line at the oldest supported release
  (`go 1.26`). Pin the build toolchain with a `toolchain go1.27.x` line.
- Use what the current releases give you:
  - 1.27: generic methods, the `uuid` package (`uuid.New`, `uuid.NewV7`, `uuid.Parse`),
    `encoding/json/v2`, and the `goroutineleak` profile.
  - 1.26: `errors.AsType`, the rewritten `go fix` with modernizers, Green Tea GC on by default.
  - 1.25: `sync.WaitGroup.Go`, `testing/synctest`, container-aware `GOMAXPROCS`,
    `http.CrossOriginProtection`.
  - 1.24: `os.Root`, `t.Context()`, `b.Loop()`, `tool` directives in `go.mod`.
- Drop third-party packages the standard library now covers (`github.com/google/uuid` on 1.27
  modules, routers used only for method/path matching).

## Toolchain

- Format with `gofmt` + `goimports` through `golangci-lint fmt`; lint with golangci-lint v2
  (`version: "2"` config, `formatters` section). `gosimple` and `stylecheck` no longer exist —
  they are part of `staticcheck`.
- Enable at least: the `standard` set (errcheck, govet, ineffassign, staticcheck, unused) plus
  gosec, errorlint, bodyclose, noctx, sloglint.
- `//nolint:<linter> // reason` only — never a bare `//nolint`.
- `govulncheck ./...` in CI; it reports only vulnerabilities your code actually reaches.
- Dev tools pinned as `tool` directives (`go get -tool golang.org/x/vuln/cmd/govulncheck`, run
  with `go tool govulncheck`). Install golangci-lint from its release binary or official action at a
  pinned version.
- `go fix ./...` after each Go upgrade to apply modernizers; review the diff like any change.
- `go mod tidy -diff` in CI fails on drift; commit `go.sum`.
- Config, `go.mod`, and CI samples: `reference/tooling.md` — read when setting up or changing lint
  or CI.

## Structure

```
cmd/orders/main.go          # wiring only: config, adapters, server, signals
internal/
  order/                    # one package per bounded context
    order.go                # domain types, invariants, sentinel errors
    service.go              # use cases; depends on interfaces declared here
    store.go                # port: type Store interface { ... }
  postgres/                 # adapter implementing order.Store
  httpapi/                  # inbound adapter: handlers, DTOs, error mapping
  config/
```

- Application code lives in `internal/`; `pkg/` only for code meant for other modules.
- Declare interfaces in the consuming package, keep them small (1–3 methods), accept interfaces,
  return concrete types.
- Vendor SDKs (cloud, payment, email) appear only in adapter packages.
- Packages: short, lowercase, no stutter (`order.Service`, not `order.OrderService`). Acronyms keep
  case (`UserID`, `HTTPClient`). Doc comments on every exported identifier.
- Constants use Go's MixedCaps (`maxBodyBytes`, `DefaultTimeout`), not `SCREAMING_SNAKE_CASE` —
  Go linters flag ALL_CAPS names; the named-constant rule still applies.

## Errors

- Check every error. Wrap with context: `fmt.Errorf("loading order %s: %w", id, err)`.
- Sentinel errors for expected conditions (`var ErrNotFound = errors.New("order not found")`);
  typed errors when callers need fields.
- Match with `errors.Is`; extract with `errors.AsType[*ValidationError](err)` (1.26+) instead of
  `errors.As` with a pointer target. Never compare error strings.
- Map domain errors to HTTP/gRPC status in the inbound adapter, in one function. Log unexpected
  errors once, at the edge — do not log and return the same error.
- `panic` only for programmer errors; recover in server middleware so one request cannot crash the
  process.

## Concurrency

- `context.Context` is the first parameter of anything that blocks or does I/O; honor cancellation.
- `errgroup.Group` (with `SetLimit`) for fan-out that can fail; `wg.Go(func() { ... })` for
  fire-and-wait without errors.
- Every goroutine has an owner and a way to stop. Close channels from the sender only; annotate
  direction (`<-chan T`, `chan<- T`).
- Prefer `sync.Mutex` for shared state; channels for ownership transfer.
- `-race` in CI. Use the `goroutineleak` pprof profile when goroutine counts creep up.
- Do not set `GOMAXPROCS` manually in containers — the runtime reads the cgroup CPU limit.

## HTTP services

- Standard `http.ServeMux` patterns: `mux.HandleFunc("GET /orders/{id}", h.getOrder)` and
  `r.PathValue("id")`. Reach for chi only when you need its middleware ecosystem.
- `http.Server` always sets `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`;
  graceful shutdown via `signal.NotifyContext` + `srv.Shutdown(ctx)`.
- Limit bodies with `http.MaxBytesReader`; decode into DTOs, validate, then convert to domain
  types.
- Outbound calls: shared `http.Client` with a `Timeout`, requests built with
  `http.NewRequestWithContext`, response bodies always closed.
- Consistent error body: `{"error":{"code":"NOT_FOUND","message":"order not found"}}`.
- Full handler, server, and middleware example: `reference/http-service.md` — read when building
  an HTTP service.

## Security

- SQL through `database/sql`/pgx placeholders (`$1`) or sqlc — never `fmt.Sprintf` into queries.
- `os/exec` with an argument list, never `sh -c` with input.
- User-influenced file paths go through `os.Root` (`os.OpenRoot(dir)`) to block traversal.
- `crypto/rand` for tokens and secrets (never `math/rand`); `crypto/subtle.ConstantTimeCompare`
  for secret comparison; passwords with `golang.org/x/crypto/argon2` or `bcrypt`.
- HTML only via `html/template`. Cookie-authenticated browser endpoints wrap handlers with
  `http.NewCrossOriginProtection().Handler(...)`.
- TLS clients keep default verification; set `MinVersion: tls.VersionTLS12` or higher on servers.
- Authorization in the service layer using the authenticated principal from `context`, never IDs
  from the request body.
- Secrets from environment/secret manager at startup; never logged, never in `go.mod` replace paths
  or build flags.

## Observability

- `log/slog` with `slog.NewJSONHandler` in production; pass the logger explicitly or via the
  composition root, and use the `...Context` methods (`logger.InfoContext(ctx, ...)`).
- Typed attributes (`slog.String`, `slog.Int`), snake_case keys, no secrets or PII. `sloglint`
  enforces consistency.
- OpenTelemetry: wrap the router with `otelhttp.NewHandler` and client transports with
  `otelhttp.NewTransport` (`go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`);
  bridge logs with `go.opentelemetry.io/contrib/bridges/otelslog` so records carry trace ids.
- `net/http/pprof` only on an internal admin listener, never on the public mux.

## Testing

- `foo_test.go` next to `foo.go`; `package foo_test` for public API tests.
- Table-driven tests with `t.Run`; `t.Parallel()` where safe; `t.Context()` for per-test contexts.
- Assertions with the standard library or `testify/require` — one style per repo.
- Time and concurrency: `testing/synctest` (`synctest.Test`, fake clock, `synctest.Wait`); on 1.27,
  `httptest.NewTestServer` for in-memory HTTP.
- Fuzz parsers and decoders (`func FuzzX(f *testing.F)`); commit interesting corpus entries in
  `testdata/fuzz/`.
- Benchmarks use `for b.Loop() { ... }`.
- Adapters get integration tests with `testcontainers-go` against real Postgres, Kafka, etc.

## Performance

- Profile first (`pprof`, execution traces); consider PGO (`default.pgo`) for hot services.
- `sync.Pool` only when a profile shows allocation pressure from that object.
- Pre-size slices and maps when the size is known; `strings.Builder` in loops.

_Versions verified September 2026._
