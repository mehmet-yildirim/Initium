# Workflow: Security Evaluation

Security evaluation is not a one-time checklist — it runs continuously across the development
lifecycle. This guide defines when, how, and by whom security assessments are triggered for
both human-guided and autonomous development.

Risk taxonomy: **OWASP Top 10:2025**. Detailed rules and tooling live in two skills that should
stay active on every production project:

- [`security-sast`](../../../.claude/skills/security-sast/SKILL.md) — secure-coding rules mapped to
  OWASP Top 10:2025 and ASVS 5.0, plus Semgrep, CodeQL, gitleaks, TruffleHog, and OSV-Scanner usage
- [`security-supply-chain`](../../../.claude/skills/security-supply-chain/SKILL.md) — lockfiles,
  release-age cooldowns, SHA/digest pinning, SBOMs, signing, SLSA provenance, trusted publishing
  (OWASP A03:2025)

LLM-specific risks (prompt injection, tool abuse, data leakage) follow the OWASP LLM Top 10 in the
[`ai-llm-apps`](../../../.claude/skills/ai-llm-apps/SKILL.md) skill; cover them with adversarial
cases in `/eval`. The full agent-side protocol is in
[Security Evaluator](../../../.initium/docs/agent/security-evaluator.md).

## Security Evaluation Touchpoints

```
Code written (human or agent)
        │
        ▼
Pre-commit hook ──── quick secret scan (gitleaks git --pre-commit --staged, < 2s)
        │
        ▼
PR creation ──────── /security-audit pr  (OWASP + SAST on changed files)
        │                     │
        │             CRITICAL/HIGH → block merge, create issue
        │             MEDIUM/LOW → document in PR, proceed
        ▼
CI pipeline ──────── full security job (SAST + dependency CVEs + secrets + IaC/images
        │                               + workflow lint + dependency review)
        ▼
Staging deployment ── /deploy checklist: no HIGH/CRITICAL CVEs, image attestation verified
        │
        ▼
Production deployment ── security sign-off required for HIGH risk changes
        │
        ▼
Weekly ──────────────── /security-audit full (entire codebase + all deps) + CodeQL
```

What the CI security job runs (details and SHA-pinned workflows in the skills):

| Check | Tools | Gate |
|-------|-------|------|
| SAST | Semgrep (`p/owasp-top-ten`), CodeQL `security-extended` | Block on high |
| Secrets | gitleaks, TruffleHog (verified results) | Block on any finding |
| Dependency CVEs | OSV-Scanner plus the ecosystem auditor (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`) | Block on HIGH+ with a fix available |
| Dependency review | `actions/dependency-review-action` (`fail-on-severity: high`, license allowlist) | Block |
| Containers / IaC | Grype or Trivy CLI (images), Checkov or Trivy config (IaC) | Block on fixable CRITICAL |
| Workflows | actionlint, zizmor | Block on medium+ zizmor findings |

Do not use `aquasecurity/trivy-action` — its tags were hijacked in March 2026. Pin every action by
full commit SHA (see [`devops-cicd`](../../../.claude/skills/devops-cicd/SKILL.md)).

---

## When to Run /security-audit

### Always (Mandatory)
- Any PR touching: authentication, authorization, payment, user input processing, file operations, external API calls
- Any dependency upgrade (even patch version) — run upgrades through `/upgrade`, which re-audits afterwards
- Before any production deployment
- When the autonomous agent creates a PR

### Strongly Recommended
- After merging a large or complex feature branch
- When adding a new integration with an external service
- When changing data models that handle PII or financial data
- When changing CI workflows, release pipelines, or dependency-update config

### Scheduled (Automated)
- Daily: OSV-Scanner or the ecosystem auditor (`npm audit` / `pip-audit` / `govulncheck`) on all dependency manifests
- Weekly: Full SAST (including CodeQL) + dependency + secret scan of entire codebase
- Monthly: License audit for all dependencies; review the OpenSSF Scorecard trend

---

## Running /security-audit Manually

### Full codebase scan
```
/security-audit
```
or
```
/security-audit full
```

### Only the current branch changes
```
/security-audit pr
```
(A PR or branch target scans `git diff main...HEAD` — faster, used before PR creation)

### Dependencies only
```
/security-audit deps
```

### Secret scan only
```
/security-audit secrets
```

### Specific file or directory
```
/security-audit src/payments/
/security-audit src/api/users.ts
```

---

## Interpreting Results

The security audit outputs:
1. **Human-readable report** in the terminal (markdown table)
2. **JSON report** at `.agent/audit/<date>-security-report.json` (schema: [`.initium/docs/agent/schemas/security-report.json`](../../../.initium/docs/agent/schemas/security-report.json))

### Reading the overall verdict

| Verdict | Meaning | Action |
|---------|---------|--------|
| `BLOCK_DEPLOYMENT` | CRITICAL or HIGH finding in the diff | Fix before proceeding |
| `REVIEW_REQUIRED` | MEDIUM finding or HIGH with active CVE | Human security review; fix within sprint |
| `APPROVED_WITH_NOTES` | LOW / INFO findings only | Document in PR; fix when convenient |
| `CLEAN` | No findings | Proceed |

### What the autonomous agent does

| Verdict | Agent behavior |
|---------|---------------|
| `BLOCK_DEPLOYMENT` | Attempts auto-fix (CVE upgrade, obvious pattern). If fails → `/escalate critical security_vulnerability_detected` |
| `REVIEW_REQUIRED` | Adds findings to PR description. Tags PR with `security-review`. Does not block PR creation. |
| `APPROVED_WITH_NOTES` | Adds findings as PR comments. |
| `CLEAN` | Proceeds silently. |

---

## Remediation Workflow

### CRITICAL Findings

```
1. Stop current work
2. Identify the root cause (see finding.location and finding.evidence)
3. Apply fix (see finding.remediation.codeExample)
4. Re-run: /security-audit pr
5. Verify finding is gone
6. Add regression test that would catch this class of vulnerability
7. Commit fix with message: fix(security): <description> [CRITICAL]
```

If the CRITICAL finding involves a **committed secret**:
```bash
# 1. Revoke and rotate the credential IMMEDIATELY (before fixing code) — assume it is compromised
# 2. Then remove from git history:
git filter-repo --path <file> --invert-paths
# or for a specific string:
git filter-repo --replace-text <(echo "old-secret==>REMOVED")
# 3. Force push — the one sanctioned exception to "never force-push main"; needs the security
#    lead's approval, a temporary branch-protection bypass, and team coordination:
git push --force-with-lease origin main
# 4. Notify team to re-clone; ask the Git host to purge cached views of the old commits
```

Rewriting history does not un-leak a secret (forks, clones, and CI logs may keep it), which is why
rotation comes first.

### HIGH Findings

```
1. Assess exploitability in current environment
2. If exploitable in production: treat as CRITICAL
3. If not immediately exploitable: fix within current sprint
4. Create a Jira ticket: [SECURITY-HIGH] <finding title>
5. Link ticket to the PR
6. Fix + re-scan + close ticket
```

### CVE Findings

```
1. Check: is a fix version available?
   - YES: upgrade to the fixed version; test; commit
   - NO: check for workarounds in the CVE advisory
     - Workaround available: implement and document
     - No workaround: assess risk; accept or remove the dependency
   - Not affected (vulnerable code not reachable): publish an OpenVEX statement instead of
     suppressing the finding (see security-supply-chain)

2. Upgrade: `/upgrade security` applies only vulnerability-fixing upgrades, or by hand:
   Node.js: npm install <package>@<fixed-version>
   Python:  uv add "<package>>=<fixed-version>"   (or: pip install <package>==<fixed-version>)
   Java:    update <version> in pom.xml or build.gradle.kts / the version catalog
   Go:      go get <module>@<version> && go mod tidy
   .NET:    dotnet add package <package> --version <fixed>

3. Run tests after upgrade (dependency upgrade may break things)
4. Document in commit message: fix(deps): upgrade <package> to fix CVE-YYYY-NNNNN
```

If the finding is a **compromised package or action** rather than a CVE (malicious release,
hijacked tag), follow the incident steps in `security-supply-chain`: find the exposure window,
pin to the last known-good version or SHA, purge caches, rotate every secret the affected jobs
could read, and hunt for persistence.

---

## Security in Code Review

When reviewing a PR (manually or with `/review`), always check:

The full OWASP Top 10:2025 review checklist is in `security-sast`; the questions below are the
ones reviewers miss most often.

### Access Control (A01, includes SSRF)
- [ ] Does every endpoint that returns or modifies data verify the caller owns that data?
- [ ] Is there a way to access another user's data by changing an ID in the request?
- [ ] Are server-side fetches of user-supplied URLs allowlisted (no private, loopback, or metadata addresses)?

### Input Handling (A05)
- [ ] Is all external input validated with a schema before use?
- [ ] Could any input reach a database query, shell command, or template without sanitization?

### Supply Chain (A03)
- [ ] Are new dependencies deliberate (maintainers, age, provenance) and lockfiles updated?
- [ ] Are new GitHub Actions and base images pinned by SHA / digest?

### Cryptography & Secrets (A04)
- [ ] Are any credentials hardcoded (even in test files)?
- [ ] Is a CSPRNG (`crypto.randomBytes` / `secrets.token_hex`) used for security-sensitive randomness?
- [ ] Are passwords hashed with Argon2id (preferred), scrypt, or bcrypt — never MD5/SHA?

### Session & Auth (A07)
- [ ] Is the session invalidated on logout?
- [ ] Are tokens rotated on login and privilege change?
- [ ] Are JWT claims verified (signature, expiry, issuer)?

### Exceptional Conditions (A10)
- [ ] Do security decisions fail closed when a dependency (policy engine, token introspection) errors?
- [ ] Do error responses avoid stack traces and internal identifiers?

### Logging (A09)
- [ ] Could any log line contain a token, password, or PII?
- [ ] Are authentication and authorization failures logged with a request/trace ID?

---

## Security Debt Tracking

Security findings that are deferred (MEDIUM / LOW) must be tracked:

1. Create a Jira issue: `[SECURITY-MEDIUM] <title>`
2. Label: `security`, `tech-debt`
3. Sprint target: 2 sprints from discovery date
4. Review in sprint planning: is the deferred finding still relevant?

**Never suppress findings without:**
- Written justification in `.agent/security-suppressions.json`
- Expiry date set (max 6 months)
- Security lead or team lead approval (comment on the Jira ticket)

---

## Compliance Mapping

If your project has compliance requirements, map security findings to controls
(OWASP Top 10:2025 categories; NIST SP 800-53 Rev. 5; ISO/IEC 27001:2022 Annex A; PCI DSS 4.x):

| OWASP Top 10:2025 | NIST SP 800-53 | ISO 27001:2022 | PCI DSS |
|-------------------|---------------|----------------|---------|
| A01 Broken Access Control (incl. SSRF) | AC-3, AC-6 | 5.15, 8.3 | Req 7 |
| A02 Security Misconfiguration | CM-6, CM-7 | 8.9 | Req 2 |
| A03 Software Supply Chain Failures | SR-3, SR-11, SI-2 | 5.21, 8.8 | Req 6 |
| A04 Cryptographic Failures | SC-8, SC-13 | 8.24 | Req 3, 4 |
| A05 Injection | SI-10 | 8.28 | Req 6 |
| A06 Insecure Design | SA-8 | 8.25, 8.27 | Req 6 |
| A07 Authentication Failures | IA-2, IA-5 | 8.5 | Req 8 |
| A08 Software or Data Integrity Failures | SI-7 | 8.28 | Req 6 |
| A09 Security Logging and Alerting Failures | AU-2, AU-12 | 8.15, 8.16 | Req 10 |
| A10 Mishandling of Exceptional Conditions | SI-11 | 8.28 | Req 6 |

Use the JSON report's `owaspId` and `cweId` fields to generate compliance evidence artifacts.
Record `owaspId` with the edition (e.g. `A05:2025`) — IDs shifted between the 2021 and 2025
editions, so an ID without a year is ambiguous.
