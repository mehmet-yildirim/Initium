---
name: lang-kotlin
description: Kotlin backend standards — Kotlin 2.4 (K2) on JDK 25, Ktor 3.6 and Spring Boot 4 with JSpecify nullability, coroutines, kotlinx.serialization, Exposed/jOOQ/JPA, detekt, ktlint, OWASP Dependency-Check, kotlin-logging with JSON Logback, OpenTelemetry, Kotest, MockK, and Testcontainers. Use when writing, reviewing, or configuring server-side Kotlin; for Android or KMP code use mobile-android or mobile-kmp instead.
paths:
  - "**/src/main/kotlin/**"
  - "**/src/test/kotlin/**"
---

# Kotlin Backend Standards

Server-side Kotlin. Android lives in `mobile-android`, shared multiplatform code in `mobile-kmp`,
Java-only modules in `lang-java`.

## Baseline

- Kotlin 2.4 (2.4.20, September 2026); 2.4 is supported until December 2027. Plan for 2.5
  (planned December 2026).
- JDK 25 LTS via Gradle toolchains (`kotlin { jvmToolchain(25) }`).
- Ktor 3.6 (September 2026) or Spring Boot 4.x. Spring Boot 4 requires Kotlin 2.2+ and ships
  JSpecify nullness annotations that Kotlin maps to real nullable/non-null types — fix the
  resulting compiler errors on upgrade; never paper over them with `!!`.
- Spring projects: add `-Xannotation-default-target=param-property` so annotations such as
  `@NotBlank` apply to both the constructor parameter and the property.

## Build and tooling

- Gradle Kotlin DSL with a version catalog (`gradle/libs.versions.toml`); no versions in build files.
- `allWarningsAsErrors = true`; explicit API mode (`explicitApi()`) for library modules.
- Formatting with ktlint, static analysis with detekt; both gate CI.
- Dependency scanning: OWASP Dependency-Check Gradle plugin (`org.owasp.dependencycheck`, fail on
  CVSS ≥ 7) or an equivalent SCA in CI, plus Gradle dependency verification
  (`gradle/verification-metadata.xml`) to pin checksums.
- CI: `./gradlew ktlintCheck detekt test dependencyCheckAnalyze`.

## Language usage

- Immutability first: `val`, `data class` with `val` properties, read-only collection types.
- Model states with `sealed interface` hierarchies and exhaustive `when` — no boolean flag soup.
- Value classes for identifiers: `@JvmInline value class OrderId(val value: UUID)`.
- Avoid `!!`. Use `requireNotNull` / `checkNotNull` with a message for true invariants.
- Scope functions sparingly; nested `let`/`apply` chains harm readability.
- Extension functions for pure transformations, not for hiding side effects.
- Constants: `const val MAX_RETRY_COUNT = 3` in `SCREAMING_SNAKE_CASE`.

## Structure

- Feature packages per bounded context with `domain` (entities, errors, pure logic), `application`
  (use cases, port interfaces), and `adapters` (HTTP routes/controllers, persistence, clients).
- Vendor SDKs only inside adapters; domain code has no Ktor, Spring, or JDBC imports.
- Request/response DTOs are separate from domain types; map at the adapter edge.

## Errors

- Domain failures are values: sealed result types or `Result<T>`/Arrow `Either` — pick one per
  project and use it consistently.
- Exceptions only for unexpected failures; map them to HTTP responses in one central handler
  (Ktor `StatusPages`, Spring `@RestControllerAdvice` with `ProblemDetail`).
- Never catch `Throwable` or `CancellationException` without rethrowing.

## Coroutines

- Structured concurrency only: no `GlobalScope`. Launch from a scope owned by the request,
  application, or a component with a defined lifecycle.
- Wrap blocking calls (JDBC, legacy SDKs) in `withContext(Dispatchers.IO)`.
- Always set timeouts (`withTimeout`) on outbound calls; never swallow `CancellationException`.
- `Flow` for streams; `StateFlow`/`SharedFlow` for hot state, with explicit buffering policy.

## Ktor 3

- Organize by feature: routing, service, and repository per bounded context, installed as plugins.
- Serialization with `kotlinx.serialization`.
- Dependency injection through Koin or constructor wiring in `Application.module()` — no service
  locators inside routes.
- Install `CallId`, `CallLogging`, `StatusPages`, `RequestValidation`, and OpenTelemetry.
- Authentication: `ktor-server-auth` (JWT/bearer). The 3.6 type-safe schemes (`authenticateWith`)
  and the `Oidc` plugin are experimental (`@ExperimentalKtorApi`) — opt in deliberately.

## Spring Boot with Kotlin

- Constructor injection only; classes stay final (use the `kotlin-spring` plugin rather than `open`).
- Use `kotlin-jpa` plugin for entities; do not use `data class` for JPA entities.
- Prefer coroutine-based controllers (`suspend fun`) or WebFlux consistently — do not mix models.
- Configuration via `@ConfigurationProperties` data classes with `@Validated`.

## Persistence

- Exposed or jOOQ for SQL-first code; JPA when the project already standardizes on it.
- Bind parameters only — no string templates inside SQL (`"... where id = $id"` is an injection bug).
- Transactions live in the application layer, never in controllers.
- Migrations with Flyway or Liquibase (see `db-migrations`).

## Security

- Authorize in the application service using the authenticated principal (Ktor `call.principal`,
  Spring Security `Authentication`), never user or tenant IDs from the request body.
- Deny by default: every route sits inside an authentication block or is explicitly public;
  Spring Security `authorizeHttpRequests` ends with `anyRequest().authenticated()`.
- Validate every request DTO at the edge (Ktor `RequestValidation`, Jakarta Validation) before it
  reaches domain code.
- Secrets from environment or a secret manager, bound into typed config at startup; never in
  `application.conf`/`application.yaml` committed to git, never logged.
- Rate limit authentication endpoints (Ktor `RateLimit`, Spring filter or gateway).
- Password hashing with Argon2 or bcrypt (Spring Security `PasswordEncoder`); tokens from
  `SecureRandom`.

## Observability

- Log through kotlin-logging (`io.github.oshai:kotlin-logging`, 8.x) over SLF4J — never
  `println`. `private val logger = KotlinLogging.logger {}`.
- JSON output in production: Logback `ch.qos.logback.classic.encoder.JsonEncoder` or
  logstash-logback-encoder; Spring Boot can use `logging.structured.format.console=ecs`.
- Put request id and trace id in MDC (Ktor `CallId` + `callIdMdc`); for coroutines use
  `MDCContext()` from `kotlinx-coroutines-slf4j` so MDC survives suspension.
- OpenTelemetry: Ktor `KtorServerTelemetry` from `io.opentelemetry.instrumentation:opentelemetry-ktor-3.0`;
  Spring Boot 4 `spring-boot-starter-opentelemetry`. Or the OTel Java agent — not both for the same
  instrumentation.

## Testing

- Kotest (or JUnit 5) with MockK; name tests by behavior.
- Integration tests with Testcontainers for databases and brokers; Ktor `testApplication` or
  Spring `@SpringBootTest` slices for HTTP.
- Use `runTest` for coroutine code; never `Thread.sleep` in tests.
- Test authorization per role: each protected endpoint has a test proving an unauthorized caller
  is rejected.

_Versions verified September 2026._
