---
name: lang-kotlin
description: Kotlin backend standards — Kotlin 2.x (K2), Ktor 3 and Spring Boot with Kotlin, coroutines, kotlinx.serialization, Exposed/jOOQ/JPA, Kotest, MockK, Testcontainers, detekt, and ktlint. Use when writing or reviewing server-side Kotlin; for Android or KMP code use mobile-android or mobile-kmp instead.
paths:
  - "**/src/main/kotlin/**/*.kt"
  - "**/src/test/kotlin/**/*.kt"
  - "**/application.conf"
  - "**/application*.yaml"
  - "**/detekt.yml"
---

# Kotlin Backend Standards

## Build and tooling

- Gradle Kotlin DSL with a version catalog (`gradle/libs.versions.toml`); no versions in build files.
- Enable `allWarningsAsErrors` and explicit API mode for library modules.
- CI: `./gradlew ktlintCheck detekt test` plus dependency vulnerability scanning.
- Target a current LTS JDK via Gradle toolchains.

## Language usage

- Immutability first: `val`, `data class` with `val` properties, read-only collection types.
- Model states with `sealed interface` hierarchies and exhaustive `when` — no boolean flag soup.
- Value classes for identifiers: `@JvmInline value class OrderId(val value: UUID)`.
- Avoid `!!`. Use `requireNotNull` / `checkNotNull` with a message for true invariants.
- Scope functions sparingly; nested `let`/`apply` chains harm readability.
- Extension functions for pure transformations, not for hiding side effects.

## Errors

- Domain failures are values: sealed result types or `Result<T>`/Arrow `Either` — pick one per
  project and use it consistently.
- Exceptions only for unexpected failures; map them to HTTP responses in one central handler
  (Ktor `StatusPages`, Spring `@RestControllerAdvice`).

## Coroutines

- Structured concurrency only: no `GlobalScope`. Launch from a scope owned by the request,
  application, or a component with a defined lifecycle.
- Wrap blocking calls (JDBC, legacy SDKs) in `withContext(Dispatchers.IO)`.
- Always set timeouts (`withTimeout`) on outbound calls; never swallow `CancellationException`.
- `Flow` for streams; `StateFlow`/`SharedFlow` for hot state, with explicit buffering policy.

## Ktor 3

- Organize by feature: routing, service, and repository per bounded context, installed as plugins.
- Serialization with `kotlinx.serialization`; request DTOs are separate from domain types.
- Dependency injection through Koin or constructor wiring in `Application.module()` — no service
  locators inside routes.
- Install `CallLogging`, `CallId`, `StatusPages`, request validation, and OpenTelemetry.

## Spring Boot with Kotlin

- Constructor injection only; classes stay final (use the `kotlin-spring` plugin rather than `open`).
- Use `kotlin-jpa` plugin for entities; do not use `data class` for JPA entities.
- Prefer coroutine-based controllers (`suspend fun`) or WebFlux consistently — do not mix models.
- Configuration via `@ConfigurationProperties` data classes with validation.

## Persistence

- Exposed or jOOQ for SQL-first code; JPA when the project already standardizes on it.
- Transactions live in the application layer, never in controllers.
- Migrations with Flyway or Liquibase (see `db-migrations`).

## Testing

- Kotest (or JUnit 5) with MockK; name tests by behavior.
- Integration tests with Testcontainers for databases and brokers; Ktor `testApplication` or
  Spring `@SpringBootTest` slices for HTTP.
- Use `runTest` for coroutine code; never `Thread.sleep` in tests.
