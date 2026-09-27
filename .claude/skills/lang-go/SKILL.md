---
name: lang-go
description: Go development standards — idiomatic Go, standard library, testing, concurrency patterns. Use when writing or reviewing Go code.
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
  - "**/Makefile"
---

# Go Development Standards

## Code Style
- Run `gofmt` and `goimports` on every save — non-negotiable
- Use `golangci-lint` with at minimum: `errcheck`, `staticcheck`, `gosimple`, `govet`
- Line length: 100 characters recommended (not hard limit — gofmt decides)
- Comments on exported identifiers are mandatory (godoc format)
- Use `//nolint` sparingly, with justification comment

## Naming Conventions
- Packages: short, lowercase, no underscores (e.g., `user`, `httputil`, `postgres`)
- Exported identifiers: `PascalCase`
- Unexported identifiers: `camelCase`
- Interfaces: noun (what it is) or verb+er (what it does) — `Reader`, `UserStore`, `Notifier`
- Avoid redundancy: `user.UserService` → `user.Service`
- Acronyms: all-caps when exported: `HTTPClient`, `UserID`, `JSONEncoder`
- Error variables: `errNotFound`, `ErrUserNotFound` (exported)

## Project Layout
```
cmd/
├── server/         # main packages — entry points only
│   └── main.go
internal/           # private packages — not importable externally
├── user/
│   ├── service.go
│   ├── service_test.go
│   ├── repository.go  (interface)
│   └── handler.go
├── postgres/       # infrastructure implementations
└── config/
pkg/                # public packages — importable by external consumers
```
- `internal/` for all application code — prevents unintended external use
- `cmd/` for entry points; `main()` must be thin (wire deps, start server, handle signals)

## Interfaces
- Define interfaces at the consumer — not the provider
- Keep interfaces small: 1–3 methods preferred
- Accept interfaces, return concrete types
- Never embed interfaces in structs for "future extensibility"

```go
// Defined in the package that needs it (consumer)
type UserStore interface {
    GetByID(ctx context.Context, id uuid.UUID) (*User, error)
    Save(ctx context.Context, user *User) error
}
```

## Error Handling
- Check every error — never `_` on errors from external calls
- Wrap errors with context: `fmt.Errorf("getting user %s: %w", id, err)`
- Use sentinel errors for well-known conditions: `var ErrNotFound = errors.New("not found")`
- Use `errors.Is()` and `errors.As()` — never compare error strings
- Custom error types for rich error information (implement `error` interface)
- Panic only for unrecoverable programmer errors — not for expected failures

```go
user, err := s.store.GetByID(ctx, id)
if err != nil {
    if errors.Is(err, ErrNotFound) {
        return nil, ErrNotFound
    }
    return nil, fmt.Errorf("fetching user %s: %w", id, err)
}
```

## Concurrency
- Pass `context.Context` as first parameter to all blocking/I/O functions
- Honor context cancellation: check `ctx.Err()` in loops
- `sync.WaitGroup` for fan-out; `errgroup.Group` for fan-out with error collection
- Channel direction in signatures: `ch <-chan T` (receive), `ch chan<- T` (send)
- Close channels from the sender only
- Prefer `sync.Mutex` over channels for protecting shared state
- Use `-race` flag in tests and CI

## HTTP (net/http or chi/echo)
- Always set timeouts: `ReadTimeout`, `WriteTimeout`, `IdleTimeout` on `http.Server`
- Structured middleware chaining with `alice` or framework equivalent
- Decode request body with size limit: `http.MaxBytesReader`
- Write structured JSON errors: `{ "error": { "code": "...", "message": "..." } }`
- Use `chi` or `echo` for routing — `net/http` ServeMux for simple services

## Testing
- File: `foo_test.go` co-located with `foo.go`
- External test package: `package user_test` (tests public API); internal: `package user` (tests internals)
- Table-driven tests with `t.Run()`:

```go
func TestGetUser(t *testing.T) {
    cases := []struct {
        name    string
        id      uuid.UUID
        want    *User
        wantErr error
    }{
        {"found", validID, &User{...}, nil},
        {"not found", unknownID, nil, ErrNotFound},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            // arrange, act, assert
        })
    }
}
```

- Use `testify/assert` and `testify/require` for readable assertions
- `require.NoError(t, err)` stops test on failure; `assert.Equal` continues
- Integration tests: `testcontainers-go` for real databases
- `t.Parallel()` in unit tests for faster test suite

## Dependency Management
- `go.sum` committed to version control
- Minimal dependencies — prefer stdlib; add a dep only with clear justification
- `go mod tidy` run in CI to detect drift
- Vendor directory optional; CI should `go mod download` with module proxy

## Performance
- Use `sync.Pool` for frequently allocated short-lived objects
- Profile before optimizing: `pprof` for CPU/memory
- `strings.Builder` over concatenation in loops
- Avoid unnecessary allocations in hot paths: pass pointers, pre-allocate slices
- `make([]T, 0, capacity)` when size is approximately known
