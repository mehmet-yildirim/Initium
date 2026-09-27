---
name: lang-java
description: Java standards for Java 25 LTS and Spring Boot 4.1 (Spring Framework 7) — hexagonal feature packages, records and sealed types, JSpecify null safety checked by NullAway and Error Prone, Jackson 3, virtual threads, structured logging and OpenTelemetry, Spotless formatting, OWASP Dependency-Check, and JUnit 6 with @MockitoBean and Testcontainers 2. Use when writing, reviewing, or configuring Java code, Spring Boot services, Maven POMs, or Gradle builds.
globs:
  - "**/*.java"
  - "**/pom.xml"
  - "**/build.gradle"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Java Standards

Covers the language, Spring Boot services, and Java builds. Kotlin-on-JVM rules are in
`lang-kotlin`; container and CI rules are in `devops-docker` and `devops-cicd`.

## Baseline

- Target **Java 25 LTS** (`options.release = 25` / `<maven.compiler.release>25`). Java 26 and 27
  are non-LTS; adopt them only if the team upgrades every six months.
- **Spring Boot 4.1.x** (Spring Framework 7, Jakarta EE 11, Servlet 6.1). Boot 4's floor is
  Java 17, but new services target 25.
- Builds: **Gradle 9.x** (wrapper committed, version catalog `gradle/libs.versions.toml`) or
  **Maven 3.9.x** (wrapper committed). Maven 4 is still a release candidate; do not adopt it yet.
- Import the Spring Boot BOM; never hand-pin versions that the BOM already manages.

## Toolchain

- **Format:** Spotless with google-java-format (2-space indent, 100 columns, K&R braces). Run
  `spotlessCheck` in CI and `spotlessApply` locally; nobody hand-tunes formatting. On JDK 25,
  google-java-format must be 1.30.0 or newer (needed for `import module`).
- **Static analysis:** Error Prone as a compiler plugin with NullAway at `ERROR` severity. Error
  Prone 2.43+ needs JDK 21+ to run, which Java 25 satisfies.
- **Null safety:** annotate every package with JSpecify `@NullMarked` in `package-info.java`
  (sub-packages do not inherit it). Mark nullable things with `org.jspecify.annotations.Nullable`.
  Roll out NullAway with `OnlyNullMarked=true` first, then enable `JSpecifyMode=true`.
- **Dependencies:** OWASP Dependency-Check (plugin 13.x) in CI with the NVD key read from an
  environment variable (`nvdApiKeyEnvironmentVariable`), plus Dependabot/Renovate for updates.
  Fail the build on CVSS ≥ 7.
- **Lombok:** avoid in new code; records cover DTOs and value objects. If a codebase already uses
  it, declare it `compileOnly` + `annotationProcessor` in Gradle (`provided` + annotation
  processor path in Maven). Never use `@Data` or `@Builder` on JPA entities.

Read `reference/build-quality.md` when setting up or reviewing Gradle/Maven quality gates
(Spotless, Error Prone, NullAway, Dependency-Check configuration).

## Style and naming

- One top-level public type per file; the file name matches it.
- Classes, records, enums, interfaces: `PascalCase`. Methods, fields, locals: `camelCase`.
  Constants: `SCREAMING_SNAKE_CASE`. Packages: lowercase, by feature (`com.acme.orders`).
- Fields are `private final` wherever possible. Prefer immutability: records, `List.copyOf`,
  unmodifiable collections at boundaries.
- Use modern language features: records, sealed interfaces, pattern matching for `switch` and
  `instanceof`, text blocks, `var` only when the type is obvious from the right-hand side.
- Never return `null` from public methods; return `Optional<T>` for "may be absent" results
  (not for fields or parameters).

## Structure

Feature packages, each hexagonal. Dependencies point inward: adapters → application → domain.

```
com.acme.orders/
├── domain/             # entities, value objects, domain errors — plain Java, no Spring/JPA/Jackson
├── application/
│   ├── port/in/        # use-case interfaces (PlaceOrderUseCase)
│   ├── port/out/       # driven ports (OrderRepository, PaymentGateway)
│   └── PlaceOrderService.java   # implements port/in, depends only on port/out
└── adapter/
    ├── in/web/         # @RestController, request/response records, error mapping
    └── out/persistence/  # JPA entities, Spring Data repositories, port implementations
```

- The domain never imports `org.springframework`, `jakarta.persistence`, or `tools.jackson`.
- JPA entities live in the persistence adapter and are mapped to domain objects there; the web
  adapter maps domain objects to response records. Never expose entities over HTTP.
- Vendor SDKs (payment, email, cloud) are called only from `adapter/out` classes that implement
  a port. Use Spring's declarative HTTP service clients (`@HttpExchange` interfaces registered
  with `@ImportHttpServices`) inside outbound adapters for HTTP APIs.
- Constructor injection only (single constructor, no `@Autowired`). No field injection.
- Type-safe configuration with `@ConfigurationProperties` records validated with `@Validated`;
  avoid scattered `@Value`.
- Enforce the layering with ArchUnit or Spring Modulith tests.

Read `reference/spring-boot-hexagonal.md` when implementing a feature end to end (port, use
case, adapters, error mapping, and tests).

## Spring Boot 4 specifics

- Starters are modular: use `spring-boot-starter-webmvc` (renamed from `-web`), and add
  technology starters explicitly (`spring-boot-starter-flyway`, `spring-boot-starter-restclient`).
- **Jackson 3** is the default: packages moved to `tools.jackson.*` (annotations stay in
  `com.fasterxml.jackson.annotation`). Customize with `JsonMapperBuilderCustomizer` or a
  `JsonMapper` bean; an `ObjectMapper` bean no longer replaces the auto-configured one.
  `spring-boot-jackson2` is a deprecated stop-gap only.
- API versioning is built in: configure `spring.mvc.apiversion.use.header=API-Version` (or path/
  query) and use the `version` attribute on `@GetMapping` and friends.
- Undertow is not supported; use embedded Tomcat or Jetty.
- `RestTemplate` is on its way out: use `RestClient` or HTTP service clients for new code.

## Errors

- Model expected business outcomes as values: a sealed result type returned from the use case,
  pattern-matched with an exhaustive `switch` in the web adapter.
- Model invariant violations as typed domain exceptions (a sealed hierarchy rooted in one
  `DomainException extends RuntimeException`). No checked exceptions across layers.
- Map to HTTP in one `@RestControllerAdvice` returning `ProblemDetail` (RFC 9457). Enable
  `spring.mvc.problemdetails.enabled=true` so framework errors use the same format.
- Never catch `Exception`/`Throwable` without logging and rethrowing or translating. Never leak
  stack traces or SQL messages in responses.
- Validate at the edge with Bean Validation (`@Valid` on request records); invalid input is a
  400 before any use case runs.

## Persistence

- Spring Data JPA (Hibernate 7) or JDBC/jOOQ inside the persistence adapter only.
- Schema changes via Flyway or Liquibase; `spring.jpa.hibernate.ddl-auto=validate` (never
  `update`) outside local development.
- `LAZY` fetching by default; prevent N+1 with `@EntityGraph`, join fetch, or projections.
- `@Transactional` on application services (not controllers or repositories);
  `readOnly = true` for queries.
- Named parameters only (`:email`, `?1`, jOOQ bind values). Never concatenate JPQL/SQL.

## Concurrency and runtime

- Turn on virtual threads for blocking I/O services: `spring.threads.virtual.enabled=true`.
  Keep `synchronized` blocks short; Java 24+ no longer pins carrier threads on them, but lock
  contention still hurts.
- Use `ScopedValue` (final in Java 25) instead of `ThreadLocal` for request context.
  `StructuredTaskScope` is still a preview API in 25 — do not use it in production code.
- Every outbound call has connect and read timeouts (`spring.http.clients.*` or per-group
  `spring.http.serviceclient.<group>.*`).
- Enable Actuator health probes (`/actuator/health/liveness`, `/readiness`) and graceful
  shutdown (`server.shutdown=graceful`, the default in recent Boot versions).

## Security

- Spring Security 7 with a `SecurityFilterChain` bean; deny by default, then permit explicitly.
- Authorization in the application layer too (`@PreAuthorize` or explicit checks against the
  authenticated principal), never only in URL rules. Derive the user id from the security
  context, not from request bodies.
- Passwords: `PasswordEncoderFactories.createDelegatingPasswordEncoder()` (bcrypt by default) or
  Argon2. Never MD5/SHA-1.
- Secrets come from the environment or a secrets manager (Spring Cloud Vault, AWS/GCP/Azure
  secret stores); never commit them in `application.yml`.
- Expose only `health` and `info` Actuator endpoints publicly; put the rest behind auth on a
  separate management port.
- Do not deserialize untrusted data with Java serialization; never enable Jackson polymorphic
  default typing for untrusted input.

## Observability

- Log through SLF4J (`private static final Logger LOG = LoggerFactory.getLogger(X.class)`) with
  parameterized messages. Never `System.out.println` or `printStackTrace()`.
- Structured JSON logs: `logging.structured.format.console=ecs` (or `logstash`).
  Never log tokens, passwords, or PII.
- Tracing and metrics: `spring-boot-starter-opentelemetry` (Micrometer + OTLP export). Configure
  resource attributes with `management.opentelemetry.resource-attributes` or `OTEL_*` variables.
  Log export over OTLP needs a Logback/Log4j OpenTelemetry appender; Boot does not bridge logs
  on its own.
- Trace and span ids appear in log lines automatically once tracing is on; keep them.

## Testing

- **JUnit 6** (Jupiter API, drop-in for JUnit 5) + AssertJ + Mockito, via
  `spring-boot-starter-test` and the per-technology test starters
  (`spring-boot-starter-webmvc-test`, `spring-boot-starter-data-jpa-test`).
- Domain and application: plain unit tests with fakes or Mockito for ports — no Spring context.
- Web adapter: `@WebMvcTest` + `MockMvcTester` (AssertJ). Mock collaborators with
  `@MockitoBean` / `@MockitoSpyBean`; `@MockBean` and `@SpyBean` were removed in Boot 4.
- `@SpringBootTest` no longer provides MockMvc or `TestRestTemplate` automatically: add
  `@AutoConfigureMockMvc` or `@AutoConfigureRestTestClient` (`RestTestClient`).
- Persistence and integration: **Testcontainers 2** (`testcontainers-postgresql`, class
  `org.testcontainers.postgresql.PostgreSQLContainer`, no generics) with `@ServiceConnection`.
  Never H2 as a stand-in for a production database.
- Name tests `shouldDoXWhenY()` or use `@DisplayName`. Build test data with small builders or
  factory methods, not inline constructors repeated across tests.
- Architecture rules (ArchUnit/Modulith) and NullAway run as part of `check`/`verify`.

_Versions verified September 2026._
