---
name: lang-java
description: Java development standards — Spring Boot, Maven/Gradle, JUnit, clean code patterns. Use when writing or reviewing Java or Spring Boot code.
globs:
  - "**/*.java"
  - "**/pom.xml"
  - "**/build.gradle"
  - "**/build.gradle.kts"
  - "**/*.gradle"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Java Development Standards

## Code Style
- Follow Google Java Style Guide as baseline
- Indent: 4 spaces (no tabs)
- Line length: 120 characters max
- Braces: Allman-adjacent style (opening brace on same line)
- `final` on all local variables and parameters that are not reassigned
- One class per file; file name matches the public class name

## Naming Conventions
- Classes / Interfaces / Enums: `PascalCase`
- Methods / Variables: `camelCase`
- Constants: `SCREAMING_SNAKE_CASE`
- Packages: `lowercase.with.dots` (e.g., `com.company.project.feature`)
- Generic types: single uppercase letter (`T`, `E`, `K`, `V`) or descriptive (`EntityT`)
- Test classes: `ClassNameTest`; test methods: `shouldDoXWhenY()`

## Spring Boot Conventions
- Use constructor injection — NEVER field injection with `@Autowired`
- `@Service`, `@Repository`, `@Component`: one responsibility per bean
- `@RestController` + `@RequestMapping`: group by resource, not HTTP verb
- Use `@Validated` + JSR-380 annotations (`@NotNull`, `@NotBlank`, `@Size`) for input validation
- Return `ResponseEntity<T>` from controllers for full HTTP control
- Use `@ControllerAdvice` + `@ExceptionHandler` for global error handling
- Application properties: `application.yml` preferred over `application.properties`
- Use `@ConfigurationProperties` for type-safe config binding — avoid `@Value` injection

```java
// Preferred: constructor injection
@Service
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;

    public UserService(UserRepository userRepository, EmailService emailService) {
        this.userRepository = userRepository;
        this.emailService = emailService;
    }
}
```

## Architecture — Layered / Hexagonal
```
Controller (REST layer)
    ↓
Service (application/business logic)
    ↓
Repository (data access — Spring Data JPA)
    ↓
Entity / Domain model
```
- No business logic in controllers or repositories
- DTOs for request/response (never expose entity directly)
- Use `record` for immutable DTOs (Java 16+)
- MapStruct for entity ↔ DTO mapping

## JPA / Hibernate
- `@Entity` classes: no-arg constructor required; use `@Builder` + `@NoArgsConstructor` (Lombok)
- Fetch: `LAZY` by default; `EAGER` only when always needed and bounded
- Avoid N+1 queries: use `@EntityGraph`, JOIN FETCH, or batch fetching
- `@Transactional` on service methods (not controllers); read-only queries: `@Transactional(readOnly = true)`
- Use database migrations: Flyway or Liquibase — no `spring.jpa.hibernate.ddl-auto=update` in production

## Error Handling
- Use custom exceptions extending `RuntimeException`; hierarchy: `AppException → BusinessException / TechnicalException`
- Global handler via `@ControllerAdvice` maps exceptions to `ProblemDetail` (RFC 9457)
- Never catch `Exception` without logging or rethrowing
- Use `Optional<T>` for nullable returns — never return `null` from service methods

## Testing (JUnit 5 + Mockito + Spring Test)
- Unit tests: `@ExtendWith(MockitoExtension.class)` — no Spring context
- Integration tests: `@SpringBootTest` + `@Testcontainers` for real DB
- Slice tests: `@WebMvcTest` for controllers, `@DataJpaTest` for repositories
- Use `MockMvc` for controller tests; `AssertJ` for fluent assertions
- Test naming: `@DisplayName("should do X when Y")` or `shouldDoX_whenY()`
- Factories / Builders for test data — never `new Entity()` inline in tests

## Build & Dependencies
- Maven: use `<dependencyManagement>` for version control; BOM imports preferred
- Gradle: use version catalog (`libs.versions.toml`)
- Dependency scope: `test` for test-only deps; `provided` for compile-only (e.g., Lombok)
- Lombok: allowed for boilerplate (`@Getter`, `@Builder`, `@RequiredArgsConstructor`); avoid `@Data` on entities

## Java Version Standards
- Target Java 21 LTS or newer
- Use records for DTOs/value objects
- Use sealed classes for algebraic types / discriminated unions
- Use pattern matching (`instanceof` pattern, `switch` expressions)
- Use virtual threads (Project Loom) for I/O-bound work when applicable
- Text blocks for multiline strings (SQL, JSON templates)

## Security
- Never construct JPQL/SQL with string concatenation — use named parameters
- Validate inputs with Bean Validation at controller boundary
- Encode passwords with BCryptPasswordEncoder (strength ≥ 10)
- Use Spring Security — configure `SecurityFilterChain` bean (not `WebSecurityConfigurerAdapter`)
