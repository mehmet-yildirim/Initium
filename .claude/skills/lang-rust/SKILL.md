---
name: lang-rust
description: Rust development standards — Rust 1.98 stable, edition 2024 with a declared MSRV, ownership and error handling, Tokio async, Axum services, sqlx, tracing, clippy, cargo-nextest, and supply-chain checks with cargo-deny. Use when writing or reviewing Rust code or Cargo configuration.
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
  - "**/rust-toolchain.toml"
  - "**/deny.toml"
---

# Rust Development Standards

Rust services and libraries. Container builds are in `devops-docker`; migration rules in
`db-migrations`.

## Toolchain

- Current stable is Rust 1.98 (six-week cadence). Pin the toolchain in `rust-toolchain.toml`; use
  `edition = "2024"` for new crates, which requires Rust 1.85 or newer.
- Declare the MSRV with `rust-version` in `Cargo.toml` (`[workspace.package]` for workspaces) and
  run CI once on that version so the promise is tested. Libraries keep the MSRV conservative;
  applications may track the pinned toolchain.
- CI runs `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`,
  `cargo nextest run`, and `cargo deny check` (licenses, advisories, bans, sources).
- Workspaces: shared dependency versions in `[workspace.dependencies]`; one crate per bounded
  context (`domain`, `application`, `infra`, `api`) mirroring the hexagonal layers.

## Error handling

- Libraries define typed errors with `thiserror`; binaries and top-level handlers may use `anyhow`.
- Never `unwrap()` / `expect()` on fallible input in production paths. `expect` is acceptable only
  for true invariants and must state the invariant in its message.
- Propagate with `?`; add context at layer boundaries (`.context("loading user profile")`).
- Map domain errors to HTTP status codes in one place (an `IntoResponse` impl), not per handler.

## Ownership and API design

- Accept borrowed types in parameters (`&str`, `&[T]`, `impl AsRef<Path>`); return owned types.
- Prefer newtypes for domain identifiers (`struct UserId(Uuid)`) over raw primitives.
- Make invalid states unrepresentable with enums; avoid `Option` fields that are "set later".
- Keep `unsafe` out of application code. Any `unsafe` block needs a `// SAFETY:` comment proving
  the invariants and a dedicated test.
- Derive `Debug` everywhere except types holding secrets; wrap secrets in `secrecy::SecretString`.

## Async (Tokio)

- Never block the runtime: move CPU-heavy or blocking I/O to `tokio::task::spawn_blocking`.
- Every outbound call gets a timeout (`tokio::time::timeout` or client-level config).
- Use `tokio::select!` with cancellation-safe futures only; document cancellation behavior.
- Shared state: `Arc<T>` with interior `RwLock`/`Mutex` from `tokio::sync` only when held across
  `.await`; otherwise `std::sync` is faster.
- Graceful shutdown: handle SIGTERM, stop accepting, drain in-flight requests.

## Axum services

- Handlers are thin: extract → call application service → map result. No SQL in handlers.
- Share dependencies through `State<AppState>` holding trait objects (ports), which keeps
  handlers testable with fakes.
- Validate request bodies at the edge (`validator` or explicit constructors) before domain calls.
- Add `tower-http` layers for tracing, request ids, timeouts, compression, and CORS.

## Data access

- `sqlx` with compile-time checked queries (`query!` / `query_as!`) and offline metadata committed
  (`cargo sqlx prepare`) so CI builds without a database.
- Migrations via `sqlx migrate`; never string-format SQL.

## Configuration and security

- Load configuration once at startup into a typed struct (`serde::Deserialize`, e.g. with `figment`
  or `config`), validate it, and fail fast; pass it down explicitly — no global mutable config.
- Secrets come from the environment or a secret manager, are held as `SecretString`, and are
  exposed only at the call site that needs them (`expose_secret()`); never log or `Debug` them.
- Authorization happens in the application service using the authenticated principal carried in
  request state, never IDs taken from the request body.
- Parameterized queries only (sqlx bind parameters); `std::process::Command` with explicit args,
  never a shell string built from input.
- Password hashing with `argon2`; token randomness from the OS CSPRNG (`getrandom`), never a
  seeded, non-cryptographic PRNG.
- `cargo deny check advisories` (RustSec) fails CI on known vulnerabilities; review new transitive
  dependencies with `cargo tree` before merging.

## Observability

- `tracing` + `tracing-subscriber` with JSON output in production; `#[instrument(skip(secret))]`
  on service boundaries. Export via OpenTelemetry (`tracing-opentelemetry`).

## Testing

- Unit tests in the same file (`#[cfg(test)] mod tests`); integration tests in `tests/`.
- Property tests with `proptest` for parsers and domain invariants.
- Database tests use Testcontainers or `#[sqlx::test]` with isolated databases.
- Snapshot tests (`insta`) for serialized API responses.

_Versions verified September 2026._
