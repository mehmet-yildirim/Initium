# Security Evaluator — Architecture & Operations Guide

The security evaluator is a cross-cutting concern that runs at multiple points in both the
human-guided and autonomous development workflows. This document describes its architecture,
integration points, severity handling, and remediation workflow.

Secure-coding rules (OWASP Top 10:2025, ASVS 5.0) and scanner usage live in the
[`security-sast` skill](../../../.claude/skills/security-sast/SKILL.md); dependency, SBOM and
action/image pinning rules live in
[`security-supply-chain`](../../../.claude/skills/security-supply-chain/SKILL.md). The command is
`/security-audit [full | <path> | pr | deps | secrets]`; its JSON report follows
[`schemas/security-report.json`](schemas/security-report.json) and is saved to
`.agent/audit/<date>-security-report.json`.

---

## Why a Dedicated Security Evaluator?

Standard QA (`/qa`) validates correctness, coverage, and code quality. Security evaluation
is a distinct concern because:

1. **Different tools**: SAST scanners, CVE databases, secret detectors — not covered by linters or test runners
2. **Different expertise**: OWASP patterns require security-specific knowledge
3. **Different thresholds**: A CRITICAL security finding blocks deployment even if all tests pass
4. **Audit requirements**: Security findings must be logged, tracked, and signed off
5. **Autonomous agents produce more code, faster** — security gates must be automated

---

## Integration Points

### In Human-Guided Development

```
Developer workflow:
  /implement ──▶ /qa ──▶ /security-audit ──▶ /review ──▶ PR open
                              │
                     CRITICAL/HIGH found?
                              │
                    YES: Fix before PR
                    NO:  Proceed with findings documented in PR
```

When to run `/security-audit`:
- Before every PR that touches: auth, authorization, user input handling, payments, data export, external API integration
- After every dependency upgrade
- Weekly full scan of the entire codebase
- Before every production deployment

### In the Autonomous Agent Loop

Security is a mandatory gate in `/loop` Phase 5: `/qa` runs its security review and dependency
audit, and any security issue in the QA report escalates before a PR is created. For changes
that touch the areas listed above, also run `/security-audit pr` on the branch before the PR:

```
/loop execution:
  ...implement... ──▶ /qa (security + deps gates) ──▶ [/security-audit pr] ──▶ create PR
                                     │
                         Security issue / CRITICAL-HIGH finding?
                                     │
                   YES: /escalate critical security_vulnerability_detected
                   NO (MEDIUM/LOW only): include findings in PR description
                                         proceed with creating PR
```

The agent **never creates a PR** with CRITICAL or HIGH security findings unresolved.

### In CI Pipeline

Security evaluation also runs in CI as an independent quality gate, catching any findings
that might have slipped through:

Pin actions by full commit SHA and scanner images by digest (tags are mutable — see
`devops-cicd` and `security-supply-chain`). Resolve digests for the releases you choose with
`docker buildx imagetools inspect <image>:<tag>`.

```yaml
# .github/workflows/ci.yml — add this job
  security:
    name: Security Scan
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    env:
      SEMGREP_IMAGE: semgrep/semgrep:<version>@sha256:<digest>
      GITLEAKS_IMAGE: ghcr.io/gitleaks/gitleaks:<version>@sha256:<digest>
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0  # Full history for secret scanning
          persist-credentials: false

      - name: Dependency CVE Audit
        run: |
          # Adjust for your stack:
          npm audit --audit-level=high        # Node.js
          # pip-audit                         # Python
          # govulncheck ./...                 # Go
          # dotnet list package --vulnerable --include-transitive  # .NET

      - name: SAST — Semgrep
        run: |
          docker run --rm -v "$PWD:/src" -w /src "$SEMGREP_IMAGE" \
            semgrep scan --config p/owasp-top-ten --config p/secrets \
            --error --sarif --output semgrep.sarif

      - name: Secret Scanning — Gitleaks
        run: |
          docker run --rm -v "$PWD:/repo" "$GITLEAKS_IMAGE" \
            git /repo --redact --exit-code 1

      - name: Upload Security Report
        if: always()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: security-report-${{ github.sha }}
          path: semgrep.sarif
          if-no-files-found: ignore
```

To surface findings in the Security tab, upload the SARIF with
`github/codeql-action/upload-sarif` (pinned SHA in `security-supply-chain` →
`reference/ci-workflows.md`) and grant the job `security-events: write`.

---

## Severity Classification

### Severity Levels & Actions

| Severity | Definition | Agent Action | Human Action |
|----------|-----------|-------------|-------------|
| **CRITICAL** | Exploitable vulnerability with direct business impact (RCE, auth bypass, data breach) | Block PR creation. `/escalate critical`. Do not deploy. | Fix immediately. Security lead review required before merge. |
| **HIGH** | Significant vulnerability, likely exploitable (SQL injection, insecure deserialization, hardcoded secret) | Block PR creation. Attempt auto-fix. If fix fails → `/escalate critical security_vulnerability_detected` (the trigger is always CRITICAL). | Fix before this sprint ends. |
| **MEDIUM** | Vulnerability requiring specific conditions to exploit (missing rate limit, weak cipher for non-sensitive data) | Create PR with findings documented. No block. | Fix within 2 sprints. Add to security backlog. |
| **LOW** | Defense-in-depth improvement (missing security header, verbose error messages) | Include in PR description as notes. | Fix when convenient. |
| **INFO** | Informational — no immediate risk | Log only. | Track for awareness. |

### CVSS Score → Severity Mapping (for CVEs)

| CVSS Score | Severity |
|-----------|---------|
| 9.0 – 10.0 | CRITICAL |
| 7.0 – 8.9  | HIGH |
| 4.0 – 6.9  | MEDIUM |
| 0.1 – 3.9  | LOW |
| 0.0        | INFO |

---

## Autonomous Agent Security Gate — Detailed Flow

```
After /implement (all tasks committed to branch):
                │
                ▼
    Run /security-audit pr
    (scans the git diff main...HEAD + dependency manifests)
                │
    ┌───────────────────────────────────────────────────┐
    │ Parse security-report.json                        │
    │ Check: ciGate.blockMerge == true?                 │
    └───────────────────────────────────────────────────┘
                │
    ┌───────────┬──────────────────────────────────┐
    │ CRITICAL or HIGH findings?                   │
    └──────────────────────────────────────────────┘
         │ YES                           │ NO
         ▼                               ▼
  Attempt auto-remediation:        Proceed to PR creation
  ─ CVE with upgrade available?
    → upgrade package + commit
    → re-run security-audit
    │
  ─ CRITICAL code pattern?
    → apply known fix pattern
    → re-run security-audit
    │
  ─ Still CRITICAL/HIGH after retry?
    → /escalate critical
        security_vulnerability_detected
    → BLOCK — await AGENT_RESUME
         │
    Human reviews + fixes
    → AGENT_RESUME
    → re-run security-audit
    → if clean → proceed to PR creation
```

### Auto-Remediation Capabilities

The agent can automatically fix:

| Finding | Auto-fix |
|---------|---------|
| CVE in `package.json` with non-breaking upgrade | `npm update <package>` + commit |
| CVE in `pyproject.toml` with available patch | Bump the constraint to the fixed version, re-lock (`uv lock` / `poetry lock`) + commit |
| CVE in `go.mod` | `go get <module>@<fixed>` + `go mod tidy` + commit |
| Hardcoded secret in new file (never committed) | Remove the secret, add to `.env.example`, load from env |
| Missing `HttpOnly` / `Secure` cookie flag | Apply the flag in the response configuration |

The agent **cannot** auto-fix:
- Logic-level access control flaws (require understanding business rules)
- SQL injection in complex query builders (risk of breaking behavior)
- Deserialization vulnerabilities (require architectural change)
- Secrets that have already been committed to git history (require `git filter-repo`)

---

## Scheduled Security Scans

Beyond per-PR scans, schedule these recurring security evaluations:

| Scan | Frequency | Scope | Trigger |
|------|-----------|-------|---------|
| Full SAST | Weekly | Entire codebase | Cron every Monday 02:00 |
| Dependency CVE | Daily | All dependency manifests | Cron or Dependabot |
| Secret scan | On every push | Full git history delta | CI hook + pre-commit |
| IaC scan | On infra changes | Terraform / K8s / Dockerfiles / workflows | CI on path filter |
| License audit | Monthly | All dependencies | Cron |

### Systemd Timer for Weekly Full Scan

```ini
# /etc/systemd/system/ai-agent-security-scan.service
[Unit]
Description=AI Agent — Weekly Full Security Scan

[Service]
Type=oneshot
User=ai-agent
WorkingDirectory=/opt/ai-agent/project
EnvironmentFile=/opt/ai-agent/.env
# Adjust the path to `command -v claude`; -p runs Claude Code headless (non-interactive)
ExecStart=/usr/bin/claude -p "/security-audit full"
StandardOutput=append:/var/log/ai-agent/security-scan.log

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/ai-agent-security-scan.timer
[Timer]
OnCalendar=Mon *-*-* 02:00:00
Persistent=true
Unit=ai-agent-security-scan.service

[Install]
WantedBy=timers.target
```

---

## Security Finding Lifecycle

### Issue Tracker Integration

CRITICAL and HIGH findings automatically create tracker issues:

```
CRITICAL finding detected:
  1. Create Jira issue:
     Type:    Bug
     Priority: Highest
     Labels:  security, critical, agent-security-finding
     Summary: [SECURITY-CRITICAL] <finding title>
     Description: <full finding from security-report.json>
     Due date: TODAY (CRITICAL) / end of sprint (HIGH)

  2. Link to the PR that introduced the finding (if known)
  3. Assign to security lead or team lead
  4. Comment on original feature PR: "Blocked by security finding: <issue-url>"
```

### Finding States

```
OPEN → IN_REMEDIATION → FIXED → VERIFIED → CLOSED
              │
              └─ ACCEPTED_RISK (needs security lead sign-off + documented justification)
              └─ FALSE_POSITIVE (mark in security-report.json; add suppression rule)
```

### Suppressing False Positives

When a finding is confirmed as a false positive, suppress it to prevent noise:

```json
// In .agent/security-suppressions.json
{
  "suppressions": [
    {
      "ruleId": "semgrep.generic.secrets.keychain",
      "path": "src/auth/keychain-helper.ts",
      "reason": "This is a wrapper around the OS keychain — not a hardcoded secret",
      "addedBy": "dev@company.com",
      "addedAt": "2024-03-09",
      "expiresAt": "2024-09-09"
    }
  ]
}
```

`/security-audit` does not load this file on its own — reference it in the audit request (or in
`AGENTS.md`) so the agent excludes suppressed findings and marks them `falsePositive` in the
report. Prefer the scanner's native suppression too (`# nosemgrep: <rule-id>`, `.gitleaksignore`)
so CI honours it. Suppressions expire — they must be renewed to prevent permanent blind spots.

---

## Security Metrics & KPIs

Track these metrics to assess security posture over time:

| Metric | Target | Source |
|--------|--------|--------|
| Mean Time to Remediate CRITICAL | < 24 hours | Jira issue created → closed |
| Mean Time to Remediate HIGH | < 1 sprint | Jira |
| Open CRITICAL / HIGH count | 0 CRITICAL, < 5 HIGH | Security report |
| Dependency CVE age (HIGH+) | < 7 days unpatched | deps scan |
| False positive rate | < 10% | suppression log |
| Secrets committed to git | 0 | gitleaks scan |
| Security findings per PR | Trending down | report history |

---

## Security Tool Stack — Recommended Setup

Install these tools on the agent host for automated scanning:

Prefer a package manager with pinned versions. Never pipe a downloaded script into a shell; for
release binaries, download a specific version and verify its published checksum before
installing.

```bash
# Semgrep — SAST (universal)
pipx install semgrep
# or: brew install semgrep

# Gitleaks — secret scanning
brew install gitleaks
# Linux: download a versioned release from https://github.com/gitleaks/gitleaks/releases
#        and verify it against the release checksums file

# TruffleHog — verified-secret scanning (used by /security-audit)
brew install trufflehog

# OSV-Scanner v2 — multi-ecosystem CVE scanning
brew install osv-scanner
# or: go install github.com/google/osv-scanner/v2/cmd/osv-scanner@<version>

# Hadolint — Dockerfile linting
brew install hadolint
# Linux: download a versioned release from https://github.com/hadolint/hadolint/releases

# Grype — container image CVE scanning
brew install grype

# Checkov — IaC security (Terraform, Kubernetes, Dockerfiles)
pipx install checkov

# actionlint — GitHub Actions workflow linting
brew install actionlint

# Language-specific (install based on project stack):
pipx install pip-audit && pipx install bandit            # Python
go install golang.org/x/vuln/cmd/govulncheck@<version>   # Go
go install github.com/securego/gosec/v2/cmd/gosec@<version>  # Go
```

Verify all tools are available:
```bash
for tool in semgrep gitleaks trufflehog osv-scanner hadolint grype checkov actionlint; do
  command -v "$tool" >/dev/null && echo "OK: $tool" || echo "MISSING: $tool"
done
```
