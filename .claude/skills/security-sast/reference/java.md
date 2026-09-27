# Java / Spring security examples

Assumes Java 21/25 LTS, Spring Boot 3.5/4.x with Spring Security 6.x/7.x. Language rules:
`lang-java`.

## Injection

```java
// BAD
stmt.execute("SELECT * FROM users WHERE id = " + userId);

// GOOD
try (PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?")) {
    ps.setObject(1, userId);
    try (ResultSet rs = ps.executeQuery()) { /* map rows */ }
}
```

- JPA: named parameters (`:id`) or Criteria API; never concatenate into JPQL/native queries.
- Logging: parameterized messages (`log.info("user {}", userId)`); keep Log4j 2 ≥ 2.17.1
  (Log4Shell class of JNDI lookups).

## XML External Entities (XXE)

```java
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
dbf.setXIncludeAware(false);
dbf.setExpandEntityReferences(false);
DocumentBuilder builder = dbf.newDocumentBuilder();
```

## Deserialization

- Never `ObjectInputStream.readObject()` on untrusted input; use JSON (Jackson) into explicit DTOs
  with polymorphic typing disabled (no default typing).
- If Java serialization is unavoidable, install an allowlist filter
  (`ObjectInputFilter.Config.setSerialFilter(...)` or `-Djdk.serialFilter=...`).

## Cryptography

```java
// BAD: MD5, SHA-1, DES, AES/ECB
// GOOD
Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");      // fresh 12-byte IV per message
PasswordEncoder encoder = Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8(); // needs Bouncy Castle
SecureRandom random = SecureRandom.getInstanceStrong();          // or new SecureRandom()
```

## Spring Security (6.x / 7.x lambda DSL)

The chained `http.csrf().disable().and()...` style is removed. Use the lambda DSL.

```java
@Configuration
@EnableWebSecurity
class SecurityConfig {

    // Browser app with cookie sessions: keep CSRF on (7.x adds csrf.spa() for SPAs)
    @Bean
    @Order(2)
    SecurityFilterChain web(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/login", "/assets/**").permitAll()
                .anyRequest().authenticated())
            .formLogin(Customizer.withDefaults())
            .csrf(csrf -> csrf.spa());
        return http.build();
    }

    // Stateless bearer-token API: no cookies, so CSRF protection is not applicable
    @Bean
    @Order(1)
    SecurityFilterChain api(HttpSecurity http) throws Exception {
        http
            .securityMatcher("/api/**")
            .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .csrf(csrf -> csrf.disable());
        return http.build();
    }
}
```

- On Spring Security 6.x, replace `csrf.spa()` with an explicit
  `CookieCsrfTokenRepository` + `CsrfTokenRequestHandler` setup (see the reference docs).
- Method security: `@EnableMethodSecurity` and `@PreAuthorize` on service methods, not only URLs.
- Actuator: expose only `health,info` publicly; everything else on a management port behind auth.

```properties
management.endpoints.web.exposure.include=health,info
management.server.port=8081
```

## SSRF and exceptional conditions

- Outbound HTTP (`RestClient`/`WebClient`/`HttpClient`): host allowlist, resolve and reject
  non-public addresses (`InetAddress#isSiteLocalAddress`, `isLoopbackAddress`,
  `isLinkLocalAddress`, `isAnyLocalAddress`), redirects off (`HttpClient.Redirect.NEVER`),
  connect and read timeouts.
- `@RestControllerAdvice` maps typed exceptions to `ProblemDetail` (RFC 9457); unknown exceptions
  become a generic 500 with the stack trace only in logs. Authorization errors fail closed.

## Tooling

- SpotBugs + FindSecBugs, Semgrep `p/java`, CodeQL `java-kotlin`.
- OWASP Dependency-Check or OSV-Scanner on `pom.xml`/Gradle lockfiles; enable Gradle dependency
  verification (`gradle/verification-metadata.xml`).
