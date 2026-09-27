# Contract, integration and browser-mode tests

## Pact 17 consumer test (V4 DSL)

`Pact` is the V4 class and `Matchers` the V3 matchers since Pact JS 16; Pact JS 17 needs
Node ≥22.

```typescript
// pact/orders-client.pact.test.ts
import path from 'node:path';
import { Matchers, Pact } from '@pact-foundation/pact';
import { describe, expect, it } from 'vitest';
import { OrdersHttpClient } from '../src/adapters/orders-http-client';

const { integer, string, uuid } = Matchers;

const provider = new Pact({
  consumer: 'web-app',
  provider: 'orders-api',
  dir: path.resolve(process.cwd(), 'pacts'),
});

describe('OrdersHttpClient', () => {
  it('fetches an order by id', async () => {
    await provider
      .addInteraction()
      .given('order 550e8400-e29b-41d4-a716-446655440000 exists')
      .uponReceiving('a request for an existing order')
      .withRequest('GET', '/orders/550e8400-e29b-41d4-a716-446655440000', (builder) => {
        builder.headers({ Accept: 'application/json' });
      })
      .willRespondWith(200, (builder) => {
        builder.jsonBody({
          id: uuid('550e8400-e29b-41d4-a716-446655440000'),
          status: string('paid'),
          totalCents: integer(4200),
        });
      })
      .executeTest(async (mockServer) => {
        const client = new OrdersHttpClient({ baseUrl: mockServer.url });
        const order = await client.getOrder('550e8400-e29b-41d4-a716-446655440000');
        expect(order.status).toBe('paid');
      });
  });
});
```

- Test the real adapter (`OrdersHttpClient`), not `fetch` directly.
- Match on type/shape (`string`, `integer`, `uuid`, `eachLike`), not exact values, unless the
  value is part of the contract.
- Only include fields the consumer actually reads.

## Provider verification

```typescript
import { Verifier } from '@pact-foundation/pact';

await new Verifier({
  provider: 'orders-api',
  providerBaseUrl: 'http://localhost:8080',
  pactBrokerUrl: process.env.PACT_BROKER_BASE_URL,
  pactBrokerToken: process.env.PACT_BROKER_TOKEN,
  providerVersion: process.env.GIT_SHA,
  providerVersionBranch: process.env.GIT_BRANCH,
  consumerVersionSelectors: [{ mainBranch: true }, { deployedOrReleased: true }],
  publishVerificationResult: process.env.CI === 'true',
  stateHandlers: {
    'order 550e8400-e29b-41d4-a716-446655440000 exists': async () => {
      await seedOrder({ id: '550e8400-e29b-41d4-a716-446655440000', status: 'paid' });
    },
  },
}).verifyProvider();
```

- State handlers seed through the provider's own repositories against a Testcontainers database.

## Deployment gate

```bash
npx pact-broker publish ./pacts --consumer-app-version "$GIT_SHA" --branch "$GIT_BRANCH"
npx pact-broker can-i-deploy --pacticipant web-app --version "$GIT_SHA" --to-environment production
# after a successful deploy
npx pact-broker record-deployment --pacticipant web-app --version "$GIT_SHA" --environment production
```

The `pact-broker` binary comes from `@pact-foundation/pact-cli`; install it as a pinned
devDependency so `npx` resolves the local binary instead of fetching an unrelated package. The CLI
reads `PACT_BROKER_BASE_URL` and `PACT_BROKER_TOKEN` from CI secrets; never commit the token.

## Testcontainers 12 integration test

```typescript
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createPool, type Pool } from '../src/adapters/db';
import { PgOrderRepository } from '../src/adapters/pg-order-repository';
import { runMigrations } from '../src/adapters/migrations';

const STARTUP_TIMEOUT_MS = 120_000;

describe('PgOrderRepository', () => {
  let container: StartedPostgreSqlContainer;
  let pool: Pool;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:17-alpine').start();
    pool = createPool(container.getConnectionUri());
    await runMigrations(pool);
  }, STARTUP_TIMEOUT_MS);

  afterAll(async () => {
    await pool.end();
    await container.stop();
  });

  it('persists and loads an order', async () => {
    const repo = new PgOrderRepository(pool);
    const saved = await repo.save({ customerId: 'c-1', totalCents: 4200 });
    expect(await repo.findById(saved.id)).toEqual(saved);
  });
});
```

- Pin image tags (or digests) to the production major version; never `latest`.
- Start one container per test file (or per worker) and isolate tests with transactions rolled
  back after each test or unique schemas.
- Run migrations exactly as production does.
- Equivalents: Testcontainers for Java (`@Testcontainers` + `@ServiceConnection` in Spring Boot),
  Go (`testcontainers-go` modules), Python (`testcontainers[postgres]`).

## Vitest 5 browser mode

```typescript
// vitest.config.ts
import { playwright } from '@vitest/browser-playwright';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    browser: {
      enabled: true,
      provider: playwright(),
      headless: true,
      instances: [{ browser: 'chromium' }],
    },
  },
});
```

```typescript
import { expect, test } from 'vitest';
import { page } from 'vitest/browser';
import { render } from 'vitest-browser-react';
import { LoginForm } from './login-form';

test('shows an error for an invalid email', async () => {
  render(<LoginForm />);
  await page.getByLabelText('Email').fill('not-an-email');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect.element(page.getByRole('alert')).toHaveTextContent('Enter a valid email address');
});
```

- Vitest 5 requires Node ≥22.12 and Vite ≥6.4; locators are strict and `toHaveTextContent` is exact
  (use `toMatchTextContent` for partial/regex).
- Use browser mode for component behavior needing real layout, focus, or events; keep full user
  journeys in Playwright.
