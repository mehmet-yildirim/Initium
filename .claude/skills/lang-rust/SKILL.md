---
name: lang-rust
description: Rust development standards — edition 2024, ownership and error handling, Tokio async, Axum services, sqlx, tracing, clippy, cargo-nextest, and supply-chain checks with cargo-deny. Use when writing or reviewing Rust code or Cargo configuration.
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
  - "**/rust-toolchain.toml"
  - "**/deny.toml"
---

# Rust Development Standards

## Toolchain

- Pin the toolchain in `rust-toolchain.toml`; use `edition = "2024"` for new crates.
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

## Observability

- `tracing` + `tracing-subscriber` with JSON output in production; `#[instrument(skip(secret))]`
  on service boundaries. Export via OpenTelemetry (`tracing-opentelemetry`).

## Testing

- Unit tests in the same file (`#[cfg(test)] mod tests`); integration tests in `tests/`.
- Property tests with `proptest` for parsers and domain invariants.
- Database tests use Testcontainers or `#[sqlx::test]` with isolated databases.
- Snapshot tests (`insta`) for serialized API responses.
