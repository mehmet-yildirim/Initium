Perform a comprehensive security evaluation of the specified target — code changes, a module,
a full codebase scan, or a dependency manifest. Works for both manual development reviews and
autonomous agent output validation.

Reads AGENTS.md, the relevant source files, and dependency manifests before producing any findings.

---

## Step 1: Determine Scan Scope

Parse `$ARGUMENTS` to identify scope:
- **Empty / "full"** → scan entire repository (dependency audit + SAST + secrets)
- **File or directory path** → scan that path only
- **PR / branch** → scan diff from `git diff main...HEAD`
- **"deps"** → dependency CVE scan only
- **"secrets"** → secret / credential scan only

Read `AGENTS.md` to identify the tech stack — language, framework, and tooling determine which
SAST rules and CVE scanners apply.

---

## Step 2: Dependency CVE Scan

Detect and run the appropriate dependency auditor for the project:

### Node.js / JavaScript
```bash
npm audit --audit-level=none --json > .agent/audit/deps-scan.json
# OR
bun audit
# Check for HIGH and CRITICAL findings
```

### Python
```bash
pip-audit --format=json --output=.agent/audit/deps-scan.json
# OR: safety check --json > .agent/audit/deps-scan.json
```

### Java (Maven)
```bash
mvn org.owasp:dependency-check-maven:check \
  -Dformat=JSON \
  -DoutputDirectory=.agent/audit/
```

### Java (Gradle)
```bash
./gradlew dependencyCheckAnalyze
```

### .NET
```bash
dotnet list package --vulnerable --include-transitive --format json \
  > .agent/audit/deps-scan.json
```

### Go
```bash
govulncheck ./... 2>&1 | tee .agent/audit/deps-scan.txt
```

### iOS (Swift Package Manager)
```bash
# Check Package.resolved for packages with known CVEs via OSV database
osv-scanner --lockfile Package.resolved --format json \
  > .agent/audit/deps-scan.json 2>/dev/null || true
```

### Android (Gradle)
```bash
./gradlew dependencyCheckAnalyze
```

### Flutter
```bash
osv-scanner --lockfile pubspec.lock --format json \
  > .agent/audit/deps-scan.json 2>/dev/null || true
```

**Report all findings. For each vulnerability:**
- Package name and version
- CVE ID and CVSS score
- Severity (CRITICAL / HIGH / MEDIUM / LOW)
- Affected version range and fixed version
- Description in one sentence
- Recommended action

---

## Step 3: SAST — Static Application Security Testing

Run language-appropriate SAST and supplement with AI code pattern analysis:

### Universal — run on all projects
```bash
# Semgrep: open-source SAST with OWASP rule sets
semgrep --config=auto \
        --config=p/owasp-top-ten \
        --config=p/secrets \
        --json \
        --output=.agent/audit/sast-results.json \
        .
```

### JavaScript / TypeScript
```bash
npx eslint . --rulesdir eslint-plugin-security/lib/rules \
  --format json > .agent/audit/eslint-security.json 2>/dev/null || true
```

### Python
```bash
bandit -r . -f json -o .agent/audit/bandit.json 2>/dev/null || true
```

### Java
```bash
# SpotBugs with FindSecBugs plugin (if Maven project)
mvn com.github.spotbugs:spotbugs-maven-plugin:spotbugs \
  -Dspotbugs.includeFilterFile=spotbugs-security-include.xml \
  2>/dev/null || true
```

### Go
```bash
gosec -fmt=json -out=.agent/audit/gosec.json ./... 2>/dev/null || true
```

### .NET / C#
```bash
dotnet build | grep -i "security\|warning SA\|CS8618" || true
```

**After running tools**, perform AI-assisted pattern analysis on the changed/target files,
checking each OWASP Top 10 category manually:

---

## Step 4: OWASP Top 10 Assessment

For each category, examine the code in scope and report findings:

### A01 — Broken Access Control
Check for:
- [ ] Missing authorization checks before resource access
- [ ] IDOR: client-supplied IDs used without server-side ownership verification
- [ ] Privilege escalation paths (user → admin without check)
- [ ] CORS misconfiguration (wildcard `*` on sensitive endpoints)
- [ ] Missing rate limiting on sensitive operations

```
Pattern (BAD): const order = await getOrder(req.body.orderId);  // No ownership check
Pattern (GOOD): const order = await getOrder(req.user.id, req.body.orderId);
```

### A02 — Cryptographic Failures
Check for:
- [ ] Sensitive data (PII, passwords, tokens) transmitted without TLS
- [ ] Weak algorithms: MD5, SHA1, DES, RC4 — in any cryptographic context
- [ ] Hardcoded encryption keys or salts
- [ ] Passwords stored without bcrypt/Argon2/scrypt
- [ ] Weak random number generators for security-sensitive values (use `crypto.randomBytes`)
- [ ] Missing HSTS / insecure cookie flags

### A03 — Injection
Check for:
- [ ] **SQL injection**: string concatenation into SQL (any language)
- [ ] **NoSQL injection**: unvalidated objects passed to MongoDB/DynamoDB operators
- [ ] **Command injection**: `exec()`, `system()`, `subprocess.run(shell=True)` with user data
- [ ] **LDAP injection**: unsanitized input in LDAP queries
- [ ] **Template injection**: user input rendered by template engines without escaping
- [ ] **XPath / XML injection**: user input in XPath expressions or XML parsers

```
Pattern (BAD):  db.query(`SELECT * FROM users WHERE id = '${req.params.id}'`)
Pattern (GOOD): db.query('SELECT * FROM users WHERE id = $1', [req.params.id])
```

### A04 — Insecure Design
Check for:
- [ ] Missing rate limiting on authentication, password reset, OTP endpoints
- [ ] Lack of account lockout after failed attempts
- [ ] Business logic flaws (e.g., can buy items at negative price)
- [ ] Insufficient anti-automation (no CAPTCHA on abuse-prone endpoints)
- [ ] Mass assignment: blindly accepting all user-provided fields as model updates

### A05 — Security Misconfiguration
Check for:
- [ ] Default credentials or example secrets left in code
- [ ] Debug mode, verbose stack traces, or dev tooling enabled in production configs
- [ ] Missing security headers (`CSP`, `X-Frame-Options`, `X-Content-Type-Options`, `HSTS`)
- [ ] Overly permissive CORS (`Access-Control-Allow-Origin: *` on auth endpoints)
- [ ] Unnecessary features, ports, or services enabled
- [ ] Cloud storage buckets configured as public
- [ ] Environment-specific secrets committed to version control

### A06 — Vulnerable and Outdated Components
This is covered by Step 2 (CVE scan). Additionally check:
- [ ] Unmaintained libraries (last release > 2 years ago, no security patches)
- [ ] Runtime/language version out of security support window

### A07 — Identification and Authentication Failures
Check for:
- [ ] Weak session token generation (non-cryptographic random)
- [ ] Session not invalidated on logout
- [ ] Tokens not rotated after privilege change (login, role change)
- [ ] JWT: `alg: none` accepted, weak secret, missing expiry (`exp` claim)
- [ ] Password reset tokens: long-lived, reusable, or guessable
- [ ] Multi-factor authentication bypassable

### A08 — Software and Data Integrity Failures
Check for:
- [ ] Deserialization of untrusted data (Java ObjectInputStream, Python pickle, PHP unserialize)
- [ ] Dependencies fetched without integrity verification (no lockfile, no SRI)
- [ ] CI/CD pipeline allows unauthorized access or injection of build artifacts
- [ ] Auto-update mechanisms without signature verification

### A09 — Security Logging and Monitoring Failures
Check for:
- [ ] Failed authentication attempts not logged
- [ ] Authorization failures not logged
- [ ] PII or sensitive data appearing in log statements
- [ ] Logs written to a location accessible by application users
- [ ] No correlation IDs in logs (makes incident response hard)

### A10 — Server-Side Request Forgery (SSRF)
Check for:
- [ ] User-controlled URLs fetched by the server (image downloaders, webhooks, proxies)
- [ ] No URL allowlist validation before fetch
- [ ] Internal metadata endpoints reachable: `169.254.169.254`, `fd00::/8`
- [ ] DNS rebinding protection absent

---

## Step 5: Secret / Credential Scan

Scan for accidentally committed secrets:

```bash
# gitleaks — scans git history and working tree
gitleaks detect --source=. --format=json \
  --report-path=.agent/audit/secrets-scan.json 2>/dev/null || \
  echo "gitleaks not installed — run: brew install gitleaks / apt install gitleaks"

# truffleHog — entropy-based scanning
trufflehog filesystem . --json > .agent/audit/trufflehog.json 2>/dev/null || true
```

Also scan manually for patterns:
- AWS access keys (`AKIA[0-9A-Z]{16}`)
- Private keys (`-----BEGIN RSA PRIVATE KEY-----`)
- Generic API keys (`[Aa]pi[_-]?[Kk]ey\s*=\s*['"][^'"]{20,}`)
- JWT secrets in config files
- Database passwords in connection strings

---

## Step 6: Infrastructure-as-Code Security (if applicable)

```bash
# Dockerfile security
hadolint Dockerfile --format=json 2>/dev/null || true

# Kubernetes manifests
kubesec scan k8s/*.yaml 2>/dev/null || true

# Terraform
checkov -d . --framework terraform --output json 2>/dev/null || true

# GitHub Actions
actionlint .github/workflows/*.yml 2>/dev/null || true
```

---

## Step 7: Compile Security Report

Produce a structured report in two formats:

### JSON (machine-readable — saved to `.agent/audit/<date>-security-report.json`)
Use the schema at `docs/guides/agent/schemas/security-report.json`.

### Markdown Summary (human-readable output)

```
## Security Audit Report
**Date**: <ISO timestamp>
**Scope**: <what was scanned>
**Overall Risk**: CRITICAL | HIGH | MEDIUM | LOW | CLEAN

---

### CRITICAL Issues (must fix before any deployment)
| # | Category | File:Line | Finding | CVE/CWE | Remediation |
|---|----------|-----------|---------|---------|-------------|
| 1 | A03 Injection | src/api/users.ts:42 | SQL string interpolation with req.params.id | CWE-89 | Use parameterized query |

### HIGH Issues (fix before next release)
...

### MEDIUM Issues (fix within 2 sprints)
...

### LOW / Informational
...

### Dependency CVEs
| Package | Version | CVE | CVSS | Severity | Fix Version |
...

### Secrets Found
| File | Line | Type | Action Required |
...

---

### Summary Metrics
- Total findings: N
- Critical: N | High: N | Medium: N | Low: N
- CVEs found: N (Critical: N, High: N)
- Secrets found: N
- OWASP categories with findings: A01, A03, ...
- Estimated remediation effort: X hours

### Recommendation
BLOCK_DEPLOYMENT | REVIEW_REQUIRED | APPROVED_WITH_NOTES | CLEAN
```

---

## Step 8: Remediation Actions

Based on findings:

**CRITICAL findings** → Block PR/deployment immediately. Create a security issue in the tracker.
```
/escalate critical security_vulnerability_detected <task-id>
  finding: <description>
  cwe: <CWE-ID>
  file: <file:line>
```

**HIGH findings** → Create a fix PR before the feature PR is merged.

**CVE with fix available** → Run the upgrade command and commit:
```bash
npm update <package>    # or: pip install <package>==<fixed-version>
```

**Secrets found** → Treat as CRITICAL:
1. Revoke the exposed credential immediately
2. Remove from git history with `git filter-repo`
3. Rotate and re-deploy

---

Target to scan (leave empty for full scan, or specify path/pr/deps/secrets): $ARGUMENTS
