# Playwright 1.63 patterns

## `playwright.config.ts`

```typescript
import { defineConfig, devices } from '@playwright/test';

const isCI = Boolean(process.env.CI);
const BASE_URL = process.env.BASE_URL ?? 'http://localhost:3000';
const AUTH_FILE = 'playwright/.auth/user.json';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: isCI ? '50%' : undefined,
  reporter: isCI ? [['blob'], ['github']] : [['html', { open: 'never' }]],
  grepInvert: isCI ? /@quarantine/ : undefined,
  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], storageState: AUTH_FILE },
      dependencies: ['setup'],
    },
    {
      name: 'mobile-safari',
      use: { ...devices['iPhone 15'], storageState: AUTH_FILE },
      dependencies: ['setup'],
    },
  ],
  webServer: {
    command: 'npm run start',
    url: BASE_URL,
    reuseExistingServer: !isCI,
    timeout: 120_000,
  },
});
```

- Add `failOnFlakyTests: isCI` once the suite is stable.
- Keep `expect` timeouts at defaults; raise per assertion only with a comment explaining why.

## Authentication setup project

```typescript
// e2e/auth.setup.ts
import { expect, test as setup } from '@playwright/test';

const AUTH_FILE = 'playwright/.auth/user.json';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var ${name}`);
  return value;
}

setup('authenticate as standard user', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(requireEnv('E2E_USER_EMAIL'));
  await page.getByLabel('Password').fill(requireEnv('E2E_USER_PASSWORD'));
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  await page.context().storageState({ path: AUTH_FILE });
});
```

- One setup test and storage-state file per role (`admin.json`, `viewer.json`); pick per spec
  with `test.use({ storageState: 'playwright/.auth/admin.json' })`.
- Tests that mutate server-side session state (logout, password change) use a fresh login.

## Typed fixtures with setup and teardown

```typescript
// e2e/fixtures/test.ts
import { test as base, expect } from '@playwright/test';
import { z } from 'zod';
import { CheckoutPage } from '../pages/checkout-page';

const OrderSchema = z.object({ id: z.string().uuid(), status: z.enum(['draft', 'paid']) });
type Order = z.infer<typeof OrderSchema>;

type Fixtures = { draftOrder: Order; checkoutPage: CheckoutPage };

export const test = base.extend<Fixtures>({
  draftOrder: async ({ request }, use) => {
    const response = await request.post('/api/test-support/orders', {
      data: { items: [{ sku: 'SKU-TEST-1', quantity: 1 }] },
    });
    expect(response.ok()).toBe(true);
    const order = OrderSchema.parse(await response.json());
    await use(order);
    await request.delete(`/api/test-support/orders/${order.id}`);
  },
  checkoutPage: async ({ page }, use) => {
    await use(new CheckoutPage(page));
  },
});

export { expect };
```

```typescript
// e2e/specs/checkout.spec.ts
import { expect, test } from '../fixtures/test';

test('pays a draft order by card', { tag: '@critical' }, async ({ checkoutPage, draftOrder }) => {
  await checkoutPage.open(draftOrder.id);
  await checkoutPage.payWithCard();
  await expect(checkoutPage.status).toHaveText('Paid');
});
```

## Mocking third parties and time

```typescript
await page.route('https://payments.example.com/**', (route) =>
  route.fulfill({ status: 200, json: { status: 'approved' } }),
);
await page.clock.install({ time: new Date('2026-01-15T10:00:00Z') });
```

## Accessibility check

```typescript
import AxeBuilder from '@axe-core/playwright';

test('checkout has no WCAG A/AA violations', async ({ page }) => {
  await page.goto('/checkout');
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
    .analyze();
  expect(results.violations).toEqual([]);
});
```

- There is no `wcag22a` tag. Scan each meaningful state (dialog open, errors shown); axe finds
  roughly a third to half of issues — manual testing is still required.

## Aria snapshots and visual regression

```typescript
await expect(page.getByRole('navigation', { name: 'Main' })).toMatchAriaSnapshot(`
  - link "Home"
  - link "Orders"
  - button "Account"
`);

await expect(page).toHaveScreenshot('checkout.png', {
  mask: [page.getByTestId('order-timestamp')],
  maxDiffPixelRatio: 0.01,
});
```

- Generate and compare screenshots only inside the official image
  (`mcr.microsoft.com/playwright:v1.63.0-noble`) so fonts and rendering match; update baselines
  with `--update-snapshots` in the same image and review the diff in the PR.

## Sharded CI workflow

```yaml
name: e2e
on: [pull_request]
permissions: {}
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    container:
      image: mcr.microsoft.com/playwright:v1.63.0-noble
    strategy:
      fail-fast: false
      matrix:
        shardIndex: [1, 2, 3, 4]
        shardTotal: [4]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version: 24
      - run: npm ci
      - run: npx playwright test --shard=${{ matrix.shardIndex }}/${{ matrix.shardTotal }}
        env:
          BASE_URL: ${{ vars.E2E_BASE_URL }}
          E2E_USER_EMAIL: ${{ secrets.E2E_USER_EMAIL }}
          E2E_USER_PASSWORD: ${{ secrets.E2E_USER_PASSWORD }}
      - if: ${{ !cancelled() }}
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: blob-report-${{ matrix.shardIndex }}
          path: blob-report
          retention-days: 3

  report:
    if: ${{ !cancelled() }}
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version: 24
      - run: npm ci
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          path: all-blob-reports
          pattern: blob-report-*
          merge-multiple: true
      - run: npx playwright merge-reports --reporter html ./all-blob-reports
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: playwright-report
          path: playwright-report
          retention-days: 7
```

- Keep the container image tag equal to the `@playwright/test` version in the lockfile.
- Secrets are not available to fork PRs; run authenticated suites on internal branches only.
