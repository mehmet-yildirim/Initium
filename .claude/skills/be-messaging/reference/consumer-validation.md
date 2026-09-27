# Validated, idempotent consumer behind a port (TypeScript, Zod 4)

Read when writing a message handler. The handler knows nothing about the broker client; a thin
adapter (KafkaJS, Confluent client, AMQP, NATS) turns broker records into `InboundMessage` and
acts on the returned outcome.

## Schema at the boundary

```ts
// src/inventory/messaging/order-placed.schema.ts
import { z } from 'zod';

export const ORDER_PLACED_V1 = 'com.acme.orders.order-placed.v1';

// z.object (not strictObject): unknown fields must be tolerated for forward compatibility.
export const OrderPlacedV1 = z.object({
  specversion: z.literal('1.0'),
  id: z.string().min(1),
  type: z.literal(ORDER_PLACED_V1),
  source: z.string().min(1),
  time: z.iso.datetime({ offset: true }),
  data: z.object({
    orderId: z.uuid(),
    lines: z
      .array(z.object({ sku: z.string().min(1), quantity: z.number().int().positive() }))
      .min(1)
      .max(500),
  }),
});

export type OrderPlacedV1 = z.infer<typeof OrderPlacedV1>;
```

## Handler

```ts
// src/inventory/messaging/order-placed.handler.ts
import type { Logger } from 'pino';
import type { ReserveStock } from '../application/reserve-stock.js';
import type { Inbox } from '../ports/inbox.js';
import { OrderPlacedV1 } from './order-placed.schema.js';

export interface InboundMessage {
  key: string | null;
  value: Uint8Array;
  headers: Readonly<Record<string, string>>;
}

export type HandleOutcome =
  | { kind: 'processed' }
  | { kind: 'duplicate' }
  | { kind: 'rejected'; reason: 'MALFORMED_JSON' | 'SCHEMA_INVALID' | 'BUSINESS_REJECTED' };

interface Dependencies {
  inbox: Inbox;
  reserveStock: ReserveStock;
  logger: Logger;
}

const decoder = new TextDecoder('utf-8', { fatal: true });

function parseJson(bytes: Uint8Array): unknown {
  try {
    return JSON.parse(decoder.decode(bytes));
  } catch {
    return undefined;
  }
}

export function createOrderPlacedHandler({ inbox, reserveStock, logger }: Dependencies) {
  return async (message: InboundMessage): Promise<HandleOutcome> => {
    const json = parseJson(message.value);
    if (json === undefined) {
      logger.warn({ key: message.key }, 'order-placed: malformed JSON');
      return { kind: 'rejected', reason: 'MALFORMED_JSON' };
    }

    const event = OrderPlacedV1.safeParse(json);
    if (!event.success) {
      // Log paths and codes only; values may contain PII.
      const issues = event.error.issues.map((issue) => ({ path: issue.path.map(String).join('.'), code: issue.code }));
      logger.warn({ key: message.key, issues }, 'order-placed: schema validation failed');
      return { kind: 'rejected', reason: 'SCHEMA_INVALID' };
    }

    // processOnce records the event id and runs the callback in one database transaction.
    const outcome = await inbox.processOnce(event.data.id, () =>
      reserveStock.execute({ orderId: event.data.data.orderId, lines: event.data.data.lines }),
    );
    if (outcome.kind === 'already-processed') return { kind: 'duplicate' };
    if (!outcome.result.ok) {
      logger.info({ eventId: event.data.id, error: outcome.result.error }, 'order-placed: rejected by domain');
      return { kind: 'rejected', reason: 'BUSINESS_REJECTED' };
    }
    return { kind: 'processed' };
  };
}
```

`Inbox.processOnce` returns `{ kind: 'already-processed' } | { kind: 'done'; result: Result<…> }`.
A thrown error (database down, timeout) means a transient failure.

## What the broker adapter does with each outcome

| Outcome | Adapter action |
|---|---|
| `processed`, `duplicate` | Commit offset / ack |
| `rejected` | Publish to the DLQ with original payload, headers, reason, and source position; then commit |
| Thrown error | Do not commit; retry with backoff (retry topic or redelivery); after the retry limit, DLQ |

Keep the retry limit and backoff in configuration, and emit a metric per outcome so dashboards
show DLQ and retry rates per event type.
