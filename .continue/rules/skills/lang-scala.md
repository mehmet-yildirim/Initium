---
name: lang-scala
description: Scala 3 standards — Scala 3.9 LTS on JDK 21/25, sbt 2 or Mill 1.x, scalafmt, scalafix, strict compiler flags, Cats Effect 3 or ZIO 2, tapir and http4s, typed errors with enums and Either, otel4s and log4cats, munit/ScalaTest, and dependency scanning. Use when writing, reviewing, or configuring Scala code, sbt or Mill builds, effect-system services, or Scala HTTP APIs.
globs:
  - "**/*.scala"
  - "**/*.sc"
  - "**/build.sbt"
  - "**/build.mill"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Scala Standards

Covers Scala 3 services and libraries. JVM runtime/container tuning shared with Java is in
`lang-java`; CI in `devops-cicd`; API contracts in `api-rest-openapi`.

## Baseline

- **Scala 3.9 LTS** (3.9.0) for new code. 3.3 LTS gets fixes for about one more year — migrate
  3.3 projects to 3.9 within that window. Scala Next (3.10) only for libraries testing ahead.
- **Scala 2.13** only for existing code bases; plan migration (`-Xsource:3`, then Scala 3).
- **JDK 21 or 25 LTS** at runtime (Scala 3.8+ requires JDK 17+). Pin the JDK in CI and the
  container image; enable virtual threads only for blocking-library workloads.
- Prefer Scala 3 idioms: `enum`, opaque types, `given`/`using`, extension methods,
  `derives`, significant indentation (pick one style per repo and enforce it with scalafmt).

## Toolchain

- Build: **sbt 2.0** (2.0.9; build definitions use Scala 3) for new builds, or sbt 1.12 where
  plugins are not yet ported. **Mill 1.x** (1.1.x, `build.mill` with `//| mill-version:`
  header) is an accepted alternative. One build tool per repo.
- Compiler flags: `-deprecation -feature -unchecked -Wunused:all -Wvalue-discard
  -Wnonunit-statement -Werror` (relax `-Werror` locally only via an env-gated setting).
- **scalafmt** 3.11.x with `runner.dialect = scala3`; CI runs `sbt scalafmtCheckAll` /
  `./mill mill.scalalib.scalafmt/checkFormatAll`.
- **scalafix** 0.14.x (`sbt-scalafix`; Mill: `mill-scalafix` plugin) with `OrganizeImports`,
  `RemoveUnused` (needs SemanticDB and `-Wunused:all`), and `DisableSyntax` (`noNulls`,
  `noReturns`, `noVars` in domain code).
- Dependencies: **Scala Steward** for updates; `sbt-github-dependency-submission` (GitHub
  dependency graph + Dependabot alerts) or `sbt-dependency-check` (OWASP) in CI.
- Wrap sbt/Mill with the checked-in launcher (`sbt` script or `./mill`); pin versions in
  `project/build.properties` or the Mill header.

## Structure

- Hexagonal modules with compiler-enforced direction:
  - `domain` — pure types, rules, and errors; depends on nothing effectful (no Cats Effect,
    ZIO, JSON, or DB libraries).
  - `app` — use cases and port traits (`trait OrderRepository[F[_]]` or a ZIO service
    trait); depends on `domain` and the effect library's typeclasses.
  - `adapters` — tapir/http4s endpoints, Doobie/Skunk repositories, Kafka, vendor SDKs.
    Vendor SDKs appear **only** here.
  - `main` — `IOApp` / `ZIOAppDefault` wiring via `Resource` / `ZLayer`.
- Model with ADTs: `enum` for closed sets, opaque types for IDs and constrained values with
  smart constructors returning `Either`.
- Keep implicits/givens local and explicit; no orphan instances in shared packages.

## Errors

- Domain errors are a sealed `enum` (`OrderError.NotFound(id)`). Return
  `F[Either[OrderError, A]]` from use cases, or `IO[OrderError, A]`/`ZIO[R, OrderError, A]` in
  ZIO. Never throw for expected outcomes.
- Reserve the effect's error channel (`Throwable` in Cats Effect) for defects and infra
  failures; convert at the adapter with `attempt`/`adaptError` into domain errors when the
  caller can act on them.
- Validate input at the edge with tapir codecs / circe decoders plus smart constructors;
  accumulate validation errors with `ValidatedNec`/`EitherNec` where users need all errors.
- Map domain errors to HTTP status in one function at the endpoint layer; error bodies carry a
  stable code, never exception messages or stack traces.
- Never use `null`, `.get` on `Option`/`Either`/`Try`, or `asInstanceOf` in application code.

## Concurrency and Runtime

- **Cats Effect 3.7** (Typelevel stack: http4s 0.23, tapir, Doobie/Skunk, fs2) or **ZIO 2**
  (zio-http, ZLayer). Pick one per service; do not mix runtimes.
- Manage every resource (pools, clients, servers) with `Resource` / `ZIO.scoped`; never leak
  blocking calls onto the compute pool — wrap them in `IO.blocking` / `ZIO.attemptBlocking`.
- Shared state via `Ref`/`Deferred` (CE) or `Ref`/`Promise` (ZIO); no `var` or mutable
  collections shared between fibers.
- Bound parallelism (`parTraverseN`, `ZIO.foreachPar(...).withParallelism(n)`) and set
  timeouts on every outbound call (`timeout`, client-level timeouts).
- Do not call `unsafeRunSync` except in `main` or test harnesses.

## Security

- SQL: Doobie `sql"... $param"` / Skunk encoders are parameterized; never splice user input
  with `Fragment.const` or string concatenation.
- Validate all external input with schema-backed codecs (tapir `Schema` + validators, circe);
  reject unknown or out-of-range values at the boundary.
- Configuration and secrets from environment or a secret manager (ciris or pureconfig); wrap
  secrets in a type whose `toString` redacts; never commit them.
- Never deserialize untrusted data with Java serialization; use JSON/Protobuf codecs.
- Keep dependency scanning green; review transitive JVM CVEs (Jackson, Netty, logback) too.

## Observability

- Never `println` in application code. Use **log4cats** (`Logger[F]`) over SLF4J/logback
  with a JSON encoder; include trace IDs in log context.
- Tracing and metrics with **otel4s** 1.1 (`otel4s-oteljava`, OTLP exporter and SDK
  autoconfigure from the OpenTelemetry Java SDK); acquire with `OtelJava.autoConfigured[IO]()`
  and configure via `OTEL_*` environment variables. ZIO: `zio-opentelemetry`.
- Wrap each use case in a span; record domain error codes as span attributes, not PII.

## Testing

- **munit** 1.3 (+ `munit-cats-effect` 2.x `CatsEffectSuite`) or **ScalaTest** 3.2; ZIO
  projects use **zio-test**. One framework per repo.
- Unit-test use cases with in-memory ports built on `Ref`; property-test domain rules with
  ScalaCheck (`munit-scalacheck`).
- Integration-test adapters against real dependencies (Testcontainers-scala) and endpoints via
  tapir stub interpreters or http4s `Client.fromHttpApp`.
- Run tests with `-Werror` builds so unused-warning regressions fail fast.

Read `reference/cats-effect-service.md` when setting up an sbt or Mill build, a tapir +
http4s endpoint with typed errors, otel4s tracing, an in-memory port, a munit test, or
scalafmt/scalafix configuration.

_Versions verified September 2026._
