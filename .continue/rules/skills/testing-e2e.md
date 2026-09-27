---
name: testing-e2e
description: End-to-end, integration and contract testing — test pyramid, Playwright 1.63 (fixtures, role locators, auth setup projects, traces, sharding, aria snapshots, visual regression), Vitest 5 browser mode, Pact 17 consumer-driven contracts with can-i-deploy, Testcontainers 12, test data management, flake policy, @axe-core/playwright, and CI integration. Use when writing or reviewing E2E, browser, contract or container-backed integration tests, Playwright config, or test pipelines.
globs:
  - "**/playwright.config.*"
  - "**/e2e/**"
  - "**/*.e2e.ts"
  - "**/pact/**"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# E2E, Integration and Contract Testing

Tests above the unit level. Unit-test conventions live in the language skills (`be-node`,
`lang-*`). Accessibility rules: `accessibility`. Pipeline structure: `devops-cicd`.

## Baseline

- Pyramid, by count: many unit tests, fewer integration tests (real DB/queue via Testcontainers),
  contract tests at every service boundary, and a small E2E suite covering critical user journeys.
- E2E budget: each journey owns revenue, security, or data integrity (sign-up, login, checkout,
  permissions). Everything else moves down the pyramid.
- Every test is independent, parallel-safe, and creates its own data.
- A test that fails without a code change is a bug: flaky tests are fixed or quarantined, never
  ignored.

## Toolchain

| Concern | Tool |
|---|---|
| Browser E2E | `@playwright/test` 1.63 (Chromium, Firefox, WebKit; mobile emulation) |
| Component tests in a real browser | Vitest 5 browser mode + `@vitest/browser-playwright` |
| Contracts (HTTP, messages) | `@pact-foundation/pact` 17 (V4 `Pact`), Pact Broker/PactFlow, `@pact-foundation/pact-cli` |
| Integration dependencies | Testcontainers 12 (`@testcontainers/postgresql`, Java/Go/Python equivalents) |
| Accessibility checks | `@axe-core/playwright` 4.13 |
| Visual regression | Playwright `toHaveScreenshot` in a pinned container image |
| Mobile native | Maestro, Detox, XCUITest, Espresso (see mobile skills) |

## Structure

- Layout: `e2e/` with `fixtures/`, `pages/` (page objects), `specs/` (`*.spec.ts` or
  `*.e2e.ts`), `auth.setup.ts`, and `playwright.config.ts` at the root.
- Test the app through its public surface: E2E drives the UI and HTTP API; contract tests exercise
  the real API client adapter against a Pact mock; integration tests exercise repository/adapter
  implementations against real infrastructure.
- Domain logic stays unit-tested behind ports; E2E never reaches into the database directly —
  seed through a test-only API or factory module behind a feature flag disabled in production.
- Extend `test` with typed fixtures for data, page objects and API clients; avoid `beforeEach`
  chains and shared mutable state.
- Page objects expose intent (`checkout.payWithCard()`), not selectors.

## Locators and assertions

- Prefer user-facing locators: `getByRole` (with `name`), `getByLabel`, `getByText`, then
  `getByTestId`. Never CSS/XPath tied to layout.
- Use web-first assertions (`await expect(locator).toBeVisible()`) that auto-wait; never
  `waitForTimeout` or manual sleeps.
- Assert structure with `toMatchAriaSnapshot` for navigation, menus and forms.
- Locators are strict: an ambiguous match fails — refine rather than `.first()`.

## Test data

- Create data per test through fixtures; delete it in fixture teardown or use unique tenant/user
  IDs so runs never collide.
- Build inputs with factories (typed builders, faker with a fixed seed); no production data or PII.
- Credentials come from CI secrets (`E2E_USER_EMAIL`, `E2E_USER_PASSWORD`) for dedicated test
  accounts with minimal roles; save authenticated state once in a setup project.
- Git-ignore `playwright/.auth/` — storage state contains live session tokens.

## Flake policy

- CI: `retries: 2`, traces `on-first-retry`; a test that passes on retry is reported as flaky.
- Track flaky tests (HTML/blob report, CI annotations). Quarantine with a `@quarantine` tag and an
  issue (`// TODO(#123): ...`), exclude it via `grepInvert` in the blocking job, fix within one
  sprint or delete.
- Verify fixes with `npx playwright test --repeat-each=20 <file>`.
- Once the suite is stable, enable `failOnFlakyTests` in CI so new flakes block merges.
- Common causes: missing awaits, shared data, time/zone dependence (use `page.clock`), animations,
  third-party calls (mock with `page.route`).

## Concurrency and runtime

- `fullyParallel: true`; workers per CI machine ≈ CPU cores; scale out with `--shard=i/n` plus the
  blob reporter and `npx playwright merge-reports`.
- Serialize only tests that share a resource you cannot partition; prefer isolating the resource.
- Keep total wall-clock E2E time under ~10 minutes per PR; run the full browser matrix nightly.
- Use `--only-changed=origin/main` for fast local feedback, never as the only CI gate.

## Security

- Run E2E against ephemeral or staging environments, never production data.
- Test the security-critical paths: unauthenticated redirects, role-based access (one storage
  state per role), CSRF-protected forms, session expiry, and IDOR attempts via the API client.
- Pin third-party GitHub Actions by SHA; upload traces/reports as short-retention artifacts —
  they can contain tokens and personal data from the test accounts.
- Test-only seed endpoints must be compiled out or hard-disabled in production builds.

## Observability

- Traces (`trace: 'on-first-retry'`), screenshots and video on failure; open with
  `npx playwright show-trace`.
- Propagate a per-test correlation ID header via `extraHTTPHeaders` so failing requests can be
  found in backend logs and OpenTelemetry traces.
- Report results in CI (GitHub reporter annotations, JUnit for dashboards); track duration and
  flake rate over time.
- Test helpers log via the test runner (`test.info().annotations`, `testInfo.attach`), not
  `console.log`.

## Testing the tests

- New E2E specs must fail when the feature is broken (verify once by breaking it locally).
- Contract tests: consumer publishes pacts on every build; provider verifies them in CI; deploys
  gate on `pact-broker can-i-deploy`.
- Accessibility: run `AxeBuilder` with WCAG 2.x A/AA tags on each key page state; zero violations
  or an issue-linked exclusion.

## References

- `reference/playwright.md` — Read when writing `playwright.config.ts`, fixtures, auth setup,
  visual or accessibility checks, or the sharded CI workflow.
- `reference/contract-and-integration.md` — Read when writing Pact consumer/provider tests,
  can-i-deploy gates, Testcontainers-backed integration tests, or Vitest browser-mode tests.

_Versions verified September 2026._
