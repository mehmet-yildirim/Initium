Perform a thorough code review of the changes in the current branch (or the specified files/diff if provided).

---

## Subagent dispatch

If a Task / Agent tool exists, spawn `initium-reviewer`
(`.claude/agents/initium-reviewer.md`) with this file and `$ARGUMENTS`. Do the
review in this context only when no subagent tool is available (disclose that in
one line). The reviewer must not edit production code. Protocol:
[subagents.md](../../.initium/docs/agent/subagents.md).

---

Review against the project's standards defined in AGENTS.md and the `.cursor/rules/` files.

## Review Checklist

For each issue found, provide:
- **Severity**: `Critical` | `Major` | `Minor` | `Suggestion`
- **File & Line**: Exact location
- **Issue**: Clear description of the problem
- **Fix**: Concrete corrected code or actionable suggestion

### Correctness
- [ ] Logic errors, off-by-one errors, incorrect conditionals
- [ ] Race conditions or concurrency issues
- [ ] Incorrect error handling or unhandled edge cases
- [ ] Missing null/undefined checks

### Security (OWASP Top 10)
- [ ] Injection vulnerabilities (SQL, command, LDAP)
- [ ] Missing input validation or sanitization
- [ ] Authorization checks missing or insufficient
- [ ] Secrets, credentials, or PII in code or logs
- [ ] Insecure dependencies

### Architecture & Design
- [ ] Layer boundaries respected (no business logic in controllers, no DB in domain)
- [ ] Appropriate abstractions (not over- or under-engineered)
- [ ] Dependency injection used correctly
- [ ] Consistent with existing patterns in the codebase

### Code Quality
- [ ] Naming clarity (variables, functions, types)
- [ ] Function size and complexity (≤ 30 lines, ≤ 3 nesting levels)
- [ ] Dead code, commented-out code, or debug statements
- [ ] Code duplication that should be extracted

### Testing
- [ ] New logic has tests
- [ ] Tests cover happy path, error cases, and edge cases
- [ ] Tests follow Arrange → Act → Assert structure
- [ ] Mocking strategy is appropriate

### Documentation
- [ ] Public API changes documented
- [ ] Complex logic has explanatory comments (why, not what)
- [ ] AGENTS.md or architecture docs updated if needed

## Summary
After the detailed review, provide:
1. **Overall assessment**: Approve / Request Changes / Needs Discussion
2. **Top 3 most important issues** to address
3. **Positive callouts**: What was done well

$ARGUMENTS
