# Workflow: Testing Strategy

A comprehensive guide to the testing approach used in AI-Native development, covering
automated test generation, test review, and maintaining a healthy test suite.

Where the detail lives:
- Project-wide test standards (naming, structure, mocking, file layout, commands): `.cursor/rules/03-testing.mdc`
- E2E, contract, and container-backed integration tests: [`testing-e2e` skill](../../../.claude/skills/testing-e2e/SKILL.md)
- Unit-test tooling per stack: the language and framework skills (`lang-*`, `be-*`, `fe-*`, `mobile-*`) — see the [skills index](../../../skills/README.md)

## Testing Philosophy

1. **Tests are specifications.** A well-written test suite documents intended behavior more
   precisely than any prose document. Write tests that would help a new developer understand
   the system.

2. **AI writes tests, humans review.** Use `/test` to generate test scaffolding, then review
   critically. AI-generated tests can be wrong, trivial, or test the wrong thing.

3. **Test the behavior, not the implementation.** Tests that break when you refactor internals
   (without changing behavior) are a liability. Tests should survive refactoring.

4. **Failing tests are signals, not noise.** A flaky test is a bug. A skipped test is
   undocumented behavior. Both must be fixed or explicitly deleted.

## Test Pyramid

```
        /\
       /  \
      / E2E \        ← Few, slow, critical user journeys
     /--------\
    / Contract \     ← At every service boundary (Pact)
   /------------\
  / Integration  \   ← Moderate, real DB/queue via Testcontainers
 /----------------\
/      Unit        \ ← Many, fast, business logic
```

### Unit Tests — The Foundation
- **What**: Single function, class, or module in complete isolation
- **When**: Write alongside implementation (not after)
- **Speed**: < 1ms each; full suite < 10 seconds (targets from `.cursor/rules/03-testing.mdc`)
- **Mocking**: Mock ALL I/O (DB, HTTP, file system, time, randomness)
- **Coverage target**: 90%+ of business logic

### Integration Tests — The Safety Net
- **What**: Multiple components working together (service + real DB, API endpoint + auth)
- **When**: After unit tests; before merging
- **Speed**: 100ms–2s each; full suite < 2 minutes
- **Mocking**: Real DB/queue via Testcontainers; mock external HTTP (MSW, WireMock)
- **Coverage target**: 100% of API endpoints, all happy paths + error cases

### Contract Tests — The Boundary Check
- **What**: A consumer's expectations of a provider API or message, verified on both sides
- **When**: Whenever two services (or a frontend and its backend) are deployed independently
- **Tools**: Pact — the consumer publishes pacts on every build, the provider verifies them in CI,
  and deploys are gated on `pact-broker can-i-deploy` (details in `testing-e2e`)

### E2E Tests — The Confidence Check
- **What**: Full user journey from UI to database and back
- **When**: Only for journeys that own revenue, security, or data integrity (sign-up, login,
  checkout, permissions); run in CI on every PR and the full browser matrix nightly
- **Speed**: 5–30s each; keep total E2E wall-clock time under ~10 minutes per PR (shard if needed)
- **Tools**: Playwright for web; Maestro, Detox, XCUITest, or Espresso for native mobile
- **Coverage target**: Top 5–10 critical user paths — everything else moves down the pyramid

Load the [`testing-e2e` skill](../../../.claude/skills/testing-e2e/SKILL.md) before writing
Playwright config, fixtures, auth setup, Pact tests, or Testcontainers-backed integration tests.
It covers role-based locators, web-first assertions, per-test data, sharding, and traces.

## AI-Assisted Test Generation

### Generating tests with /test

```
/test src/users/user.service.ts
```

The command reads the source first, then generates a complete test file with the project's
configured framework (from `AGENTS.md`), covering happy path, edge cases, error cases, and
boundary conditions. Before refactoring weakly tested code, `/refactor` adds characterization tests
that pin current behavior first. Always review:

**Check that the test actually tests something:**
```typescript
// BAD — tests implementation, not behavior
it('calls findById', () => {
  service.getUser('1');
  expect(repo.findById).toHaveBeenCalledWith('1');
});

// GOOD — tests behavior
it('returns the user when found', async () => {
  repo.findById.mockResolvedValue(mockUser);
  const result = await service.getUser('1');
  expect(result).toEqual(mockUser);
});
```

**Verify error cases are meaningful:**
```typescript
// GOOD — tests the specific error behavior
it('throws NOT_FOUND when user does not exist', async () => {
  repo.findById.mockResolvedValue(null);
  await expect(service.getUser('unknown')).rejects.toMatchObject({
    code: 'NOT_FOUND'
  });
});
```

**Check test independence:**
- Each test must be runnable in isolation
- No shared mutable state between tests
- `beforeEach` resets all mocks

### Review checklist for AI-generated tests
- [ ] Test name describes behavior (`does X when Y`)
- [ ] Arrange → Act → Assert structure clear
- [ ] Mocking strategy is appropriate for test type
- [ ] Edge cases covered (empty input, null, max values)
- [ ] Error cases covered (service failure, invalid input, not found)
- [ ] Test would actually catch a real bug

## Test Data Management

### Factory functions (required pattern)
```typescript
// factories/user.factory.ts
export function createUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    email: faker.internet.email(),
    name: faker.person.fullName(),
    role: 'user',
    createdAt: new Date(),
    ...overrides,
  };
}

// In tests — override only what matters for the test
const adminUser = createUser({ role: 'admin' });
const deletedUser = createUser({ deletedAt: new Date() });
```

**Rules:**
- Never construct test objects inline with all fields — use factories
- Factories provide sensible defaults; tests override only the relevant fields
- Seed faker with a fixed value so failures reproduce; never use production data or PII
- Keep factories in `tests/factories/` or co-located with the domain

### Database Fixtures
- Use transactions rolled back after each integration test (no cleanup code)
- Seed data: minimum needed for the test — no "kitchen sink" fixtures
- Testcontainers: fresh database per test suite (not per test, for speed)
- E2E tests never reach into the database directly — seed through fixtures or a test-only API
  that is disabled in production builds

## Specialized Testing

| Concern | Command | What it does |
|---------|---------|--------------|
| Accessibility | `/a11y [component\|page\|diff]` | WCAG 2.2 AA audit: automated checks (axe-core via `@axe-core/playwright`, `jest-axe`, `vitest-axe`; platform audits on mobile) plus a manual checklist; adds axe assertions as regression tests. See the [`accessibility` skill](../../../.claude/skills/accessibility/SKILL.md) |
| LLM features | `/eval create <feature>` / `/eval run [feature]` / `/eval compare <feature> <a> <b>` | Builds a dataset in `evals/<feature>/` with edge and prompt-injection cases, graders, and a stored baseline; `run` compares against it. Uses the `ai-llm-apps` skill |
| Performance | `/perf <symptom>` | Sets a measurable target, records a baseline (load test, profiler, `EXPLAIN ANALYZE`, Lighthouse), fixes one bottleneck at a time, and adds a regression guard (benchmark, query-count assertion, bundle budget) |
| Security-critical paths | `/security-audit` | See [Security Evaluation](05-security-evaluation.md); E2E should also cover unauthenticated redirects, per-role access, and IDOR attempts |

Deterministic assertions on LLM output belong in unit tests; quality judgments (grounding,
refusals, tone) belong in `/eval` suites, which can be non-deterministic and are tracked against a
baseline rather than pass/fail per run.

## Continuous Testing During Development

### Fast feedback loop
```bash
bun test --watch             # Re-run affected tests on file change
pytest -x --tb=short -q      # Run, stop on first failure, minimal output
go test ./... -run TestName  # Run specific test while developing
npx playwright test --only-changed=origin/main  # E2E specs affected by your branch (local only, never the CI gate)
```

### Test-driven approach (for complex logic)
1. Write the failing test first (defines expected behavior)
2. Run: confirm it fails for the right reason
3. Implement just enough to make it pass
4. Refactor while keeping tests green

### Pre-commit test run
Run the fast subset before every commit:
```bash
bun test --bail     # Stop on first failure
pytest -x -q tests/unit/  # Unit tests only pre-commit
go test -short ./...       # Skip integration tests pre-commit
```

## Maintaining Test Suite Health

### Signs of an unhealthy test suite
- Tests that always pass regardless of implementation (testing nothing)
- Flaky tests (pass sometimes, fail sometimes)
- Tests that break when internals change but behavior doesn't
- Test suite taking > 10 minutes
- Coverage declining over time

### Fixing flaky tests
1. Identify the source of non-determinism (time, randomness, async timing, shared data, external service)
2. Mock or control the source (fake clocks such as Playwright's `page.clock`, seeded randomness, `page.route` for third-party calls)
3. Verify the fix by repeating the test (e.g. `npx playwright test --repeat-each=20 <file>`)
4. If it cannot be fixed now, quarantine it: tag it (e.g. `@quarantine`), exclude it from the
   blocking CI job, and link an issue (`// TODO(#123): ...`); fix within one sprint or delete it
5. Never mark tests as `skip` without a linked issue

### Coverage regression prevention
Let the test runner enforce the threshold so CI fails when coverage drops:
```bash
bun test --coverage                  # with coverageThreshold = 0.8 under [test] in bunfig.toml
vitest run --coverage                # with coverage.thresholds in vitest.config.ts
pytest --cov=src --cov-fail-under=80
```
`/qa` reports coverage against the threshold and generates tests for significant gaps.

## Testing Matrix by Layer

| Layer | Test Type | What to Test | Mock |
|-------|-----------|-------------|------|
| Domain logic | Unit | Business rules, invariants | Everything |
| Repository | Integration | Query correctness | Real DB via Testcontainers |
| Service | Unit | Orchestration, error handling | Repository, external services |
| API Handler | Integration | Request parsing, response format, auth | Service (or real) |
| API client / service boundary | Contract | Request/response shape the consumer relies on | Provider replaced by the Pact mock |
| UI Component | Unit / browser component | Render behavior, user interactions, accessibility (axe) | API calls (MSW) |
| LLM feature | Eval | Output quality, grounding, refusals | Nothing (real model) or recorded responses |
| User journey | E2E | End-to-end flow | Third-party services only |
