Perform a full quality assurance cycle on the specified component, feature, or recent changes.

This command runs through all quality dimensions systematically. Use it before creating a PR or after completing an implementation.

---

## Subagent dispatch

If a Task / Agent tool exists, spawn `initium-qa`
(`.claude/agents/initium-qa.md`) with this file and `$ARGUMENTS`. Do the cycle in
this context only when no subagent tool is available (disclose that in one line).
Protocol: [subagents.md](../../.initium/docs/agent/subagents.md).

---

## Phase 1: Static Analysis

Run and report results for:
```bash
# Adjust commands for your project's stack
bun lint           # or: ruff check . / golangci-lint run / dotnet format --verify-no-changes
bun typecheck      # or: mypy . / vue-tsc --noEmit / dotnet build
```

For each linting issue found:
- Severity: Error | Warning
- Location: file:line
- Fix: apply the fix or explain why it should be suppressed

---

## Phase 2: Test Coverage Analysis

Run the test suite with coverage:
```bash
# Adjust for your stack
bun test --coverage
```

Report:
- Total coverage: X%
- Uncovered files or functions with significant logic
- Missing test scenarios (happy path / error cases / edge cases not yet tested)

For each coverage gap, generate the missing tests.

---

## Phase 3: Security Review

Check for common vulnerabilities:

### Injection
- [ ] No SQL/JPQL/command string interpolation with external data
- [ ] All external inputs validated and sanitized

### Authentication & Authorization
- [ ] Endpoints/actions require appropriate authentication
- [ ] Authorization checked at service layer (not just UI)
- [ ] No IDOR vulnerabilities (client-supplied IDs verified against session)

### Data Exposure
- [ ] No sensitive data (passwords, tokens, PII) in logs
- [ ] Error responses don't expose internal details or stack traces
- [ ] No secrets hardcoded or in environment files committed

### Dependencies
```bash
npm audit --audit-level=high   # or: pip-audit / govulncheck / dotnet list package --vulnerable
```
Report any HIGH or CRITICAL vulnerabilities with recommended remediation.

---

## Phase 4: Code Quality Review

### Complexity
- Identify functions > 30 lines or with > 3 nesting levels
- Suggest refactoring for each

### Duplication
- Identify repeated logic that should be extracted
- Propose the extraction with code

### Error Handling Gaps
- Functions that can fail but don't handle the error case
- Missing null/undefined guards

### Dead Code
- Unused imports, variables, functions, or exported types

---

## Phase 5: API / Contract Review (if applicable)

- Are all new API endpoints documented (OpenAPI / JSDoc)?
- Do error responses follow the project's standard format?
- Are new endpoints covered by integration tests?
- Any breaking changes to existing contracts?

---

## Phase 6: Performance Review

- Any obvious N+1 query patterns?
- Missing database indexes for new query predicates?
- Any synchronous blocking operations in async code?
- Large payloads without pagination?

---

## Phase 7: QA Report

Produce a structured report:

```
## QA Report

### Pass / Fail Summary
- Lint:        PASS | FAIL (N issues)
- Type check:  PASS | FAIL
- Tests:       PASS | FAIL (N failing)
- Coverage:    X% (threshold: Y%)
- Security:    PASS | ISSUES FOUND
- Dependencies: PASS | N vulnerabilities

### Issues Requiring Action (before PR)
1. [CRITICAL] file:line — issue — fix
2. [MAJOR] file:line — issue — fix

### Suggestions (not blocking)
1. [MINOR] file:line — suggestion

### Ready for PR: YES | NO
```

---

Target to QA: $ARGUMENTS
