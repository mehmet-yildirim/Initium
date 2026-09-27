---
name: security-sast
description: Application security review and secure-coding rules mapped to the OWASP Top 10:2025 and ASVS 5.0 — injection, access control, SSRF, crypto, secrets, deserialization, exceptional-condition handling — plus SAST and scanning tooling (Semgrep, CodeQL, gitleaks, TruffleHog, OSV-Scanner). Use when writing or reviewing security-sensitive code (auth, input handling, crypto, file or network access, error handling), triaging scanner findings, or wiring security scans into CI.
---

# Secure Coding and SAST

Universal rules and tooling live here; per-language examples live in `reference/<lang>.md`.
Supply-chain controls (SBOM, signing, pinning, provenance) are in `security-supply-chain`; prompt
injection and LLM-specific risks are in `ai-llm-apps`; workflow hardening is in `devops-cicd`.

## Baseline

- Risk taxonomy: **OWASP Top 10:2025**. Verification requirements: **OWASP ASVS 5.0.0** (target
  L2 for most applications, L3 for high-value systems).
- Treat every finding as a code defect with an owner and a fix-by date; suppressions need a
  justification comment and a tracked issue.

## Toolchain

| Concern | Tools | Gate |
|---|---|---|
| SAST (pattern) | Semgrep (`semgrep scan --config p/owasp-top-ten --sarif`) | PR, block on high |
| SAST (dataflow) | CodeQL (`github/codeql-action` v4, `security-extended` suite) | PR + weekly |
| Secrets | gitleaks (`gitleaks git`), TruffleHog (`trufflehog git file://. --results=verified,unknown`) | pre-commit + PR |
| Dependency CVEs | OSV-Scanner v2 (`osv-scanner scan source -r .`), plus ecosystem tools (`npm audit`, `pip-audit`, `safety scan`, `govulncheck`, `cargo audit`) | PR, block on high/critical with a fix available |
| Containers / IaC | Trivy or Grype (images), Checkov or Trivy config (IaC) | PR + registry |
| Language linters | Bandit (Python), `eslint-plugin-security`, `gosec`, SpotBugs + FindSecBugs (JVM) | PR |

- Upload SARIF to code scanning so findings appear on the PR diff.
- Run secret scanning on the full history once, then incrementally; rotate first, then purge.
- SBOM generation, signing and provenance: see `security-supply-chain`.

## OWASP Top 10:2025 — review checklist

| # | Category | Check before approving |
|---|---|---|
| A01 | Broken Access Control (includes SSRF) | Authorization in the service layer on every request; ownership checked with the session identity, never a client-supplied ID; deny by default; outbound URLs allowlisted |
| A02 | Security Misconfiguration | No debug/stack traces in prod; security headers (CSP, HSTS, `X-Content-Type-Options`, `frame-ancestors`); least-privilege defaults; admin/actuator endpoints not public |
| A03 | Software Supply Chain Failures | Lockfiles committed; deps and actions pinned; scans green; see `security-supply-chain` |
| A04 | Cryptographic Failures | TLS 1.3 preferred (1.2 minimum); AES-GCM / ChaCha20-Poly1305; Argon2id/scrypt/bcrypt for passwords; CSPRNG for tokens; keys in a KMS |
| A05 | Injection | Parameterized queries only; no shell with interpolated input; context-aware output encoding; no `eval` |
| A06 | Insecure Design | Threat model for new flows; rate limits and quotas; business invariants enforced server-side |
| A07 | Authentication Failures | MFA/passkeys available; lockout/backoff; session rotation on login and privilege change; tokens ≥128 bits entropy |
| A08 | Software or Data Integrity Failures | No native deserialization of untrusted data; signed updates and webhooks verified (HMAC with constant-time compare) |
| A09 | Security Logging and Alerting Failures | Auth, authz and validation failures logged with request/trace IDs; no secrets or PII in logs; alerts wired |
| A10 | Mishandling of Exceptional Conditions | Fail closed; errors caught at boundaries and mapped to safe responses; resources released on every path; no partial state left behind |

## Universal rules

### Input and output
- Validate every trust boundary (HTTP, queue messages, files, webhooks, CLI args, third-party API
  responses) with a schema: structure, types, lengths, and business rules. Reject unknown keys.
- Encode output for its context (HTML, attribute, URL, SQL identifier, shell); prefer framework
  auto-escaping. Sanitize HTML only with a maintained sanitizer (DOMPurify in JS, `nh3` in
  Python).

### Injection
- SQL/NoSQL: placeholders or query builders; allowlist identifiers (sort columns, table names).
- Commands: argument arrays, no shell; allowlist the binary and validate each argument.
- Templates, LDAP, XPath, regex: never build from raw input; bound regex input size to avoid ReDoS.

### Access control and SSRF
- Resolve the actor from the verified session/token; check permission and resource ownership in the
  service layer, not only in routes or UI.
- Outbound requests from user-controlled URLs: allowlist scheme and host, resolve DNS and reject
  private, loopback, link-local and metadata ranges, disable redirects (or re-validate each hop),
  set timeouts and response-size limits. Prefer an egress proxy with its own allowlist.

### Secrets
- No secrets in source, config committed to git, client bundles, mobile binaries, or container
  layers. Load at runtime from a secrets manager or workload identity.
- Mobile/front-end apps cannot keep secrets: call a backend that holds the credential, or exchange
  a user session for short-lived scoped tokens.
- Leaked secret: revoke and rotate immediately, then purge history; treat it as compromised.

### Cryptography
- Use platform/vetted libraries only; never implement primitives. No MD5/SHA-1 for security, no
  ECB, no static IVs, no custom token formats.
- Passwords: Argon2id (preferred), scrypt, or bcrypt with a cost reviewed yearly; rehash on login
  when parameters change.
- Compare MACs and tokens in constant time; hash both inputs first when lengths can differ.

### Files
- Resolve paths against a fixed root and verify containment (or use a rooted API such as Go
  `os.Root`); generate server-side names for uploads; check size and content type by magic bytes.
- Parse XML with DTDs/external entities disabled; parse YAML with safe loaders.

### Exceptional conditions (A10)
- Security decisions fail closed: if the policy engine, token introspection or feature-flag store
  errors, deny.
- Catch at the boundary, log once with context, return an RFC 9457 problem response without stack
  traces or internal identifiers.
- Always release locks, transactions and file handles (`finally`, `using`, `defer`, `with`).
- Set timeouts on every network call; treat timeouts and partial reads as errors, not empty data.

## Structure

- Keep security controls in dedicated modules behind ports: `AuthorizationPolicy`,
  `PasswordHasher`, `TokenVerifier`, `OutboundHttpClient` (with SSRF guard), `SecretStore`.
- Vendor SDKs (KMS, secrets manager, IdP) only inside adapters; domain code depends on the port.
- Typed security errors (`AccessDenied`, `InvalidToken`, `SsrfBlocked`) mapped to 401/403/400 at
  the edge.

## Observability

- Structured logs via the project logger with request and trace IDs; redact `Authorization`,
  cookies, tokens, passwords and PII at the logger level.
- Emit security events (login success/failure, permission denied, validation failure, rate-limit
  hit) as distinct, alertable log events or metrics.

## Testing

- Unit tests for every authorization rule, including the negative case per role.
- Regression test for each fixed vulnerability (the exploit input must now fail safely).
- DAST (OWASP ZAP baseline) against a preview environment for web apps; fuzz parsers and
  deserializers where the language has native fuzzing (Go, Rust, Java via Jazzer).

## References

- `reference/typescript.md` — Read when reviewing Node.js/TypeScript/browser code (prototype
  pollution, XSS, JWT, SSRF, fail-closed examples).
- `reference/python.md` — Read when reviewing Python services (pwdlib/argon2-cffi, pickle,
  subprocess, SSRF).
- `reference/java.md` — Read when reviewing Java/Spring code (Spring Security 6/7 lambda DSL, XXE,
  deserialization filters).
- `reference/go.md` — Read when reviewing Go code (`os.Root`, TLS 1.3, SSRF-safe dialer).
- `reference/swift.md` — Read when reviewing iOS code (Keychain, logging privacy, ATS).
- `reference/kotlin-android.md` — Read when reviewing Android code (no secrets in BuildConfig,
  Keystore + Tink, exported components).

_Versions verified September 2026._
