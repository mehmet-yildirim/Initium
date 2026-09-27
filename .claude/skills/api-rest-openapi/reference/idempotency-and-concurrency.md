# Idempotency Keys and Optimistic Concurrency

Implementation notes for the `Idempotency-Key` header and ETag / `If-Match` handling. The storage
examples use PostgreSQL with parameterized queries; adapt the SQL behind your own repository port.

## Idempotency-Key

The IETF draft expired in April 2026, but its semantics are the de facto convention:

| Situation | Response |
|---|---|
| Header missing on an operation that requires it | `400` problem+json |
| First request with a key | Process normally, store the final response |
| Retry with same key, same payload, first request finished | Replay the stored status, headers, and body |
| Retry with same key while the first request is still running | `409` (add `Retry-After`) |
| Same key, different payload | `422` |

Rules:
- Scope keys to the authenticated principal — the same key from two clients is two different keys.
- Fingerprint the request as a SHA-256 of method, route template, and the raw body bytes; do not
  re-serialize parsed JSON (key order and whitespace would change the hash).
- Store only the final response. On a transient failure (5xx, timeout) delete the record so the
  client can retry; deterministic 4xx outcomes are stored and replayed.
- Write the business change and the completed record in the same transaction when they share a
  database; otherwise a crash between them causes a duplicate on retry.
- Expire records after the documented window (e.g. 24 h) with a scheduled job.

### Schema

```sql
CREATE TABLE idempotency_records (
  principal_id    text        NOT NULL,
  idempotency_key uuid        NOT NULL,
  request_hash    bytea       NOT NULL,
  state           text        NOT NULL CHECK (state IN ('in_progress', 'completed')),
  response_status integer,
  response_body   jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (principal_id, idempotency_key)
);
```

### Claiming a key (TypeScript)

```ts
import { createHash } from 'node:crypto';

import { err, ok, type Result } from '../shared/result.js';

export interface SqlClient {
  query<Row>(sql: string, params: readonly unknown[]): Promise<{ rows: Row[] }>;
}

export type StoredResponse = { status: number; body: unknown };

export type ClaimOutcome =
  | { kind: 'claimed' }
  | { kind: 'replay'; response: StoredResponse };

export type ClaimError = 'KEY_IN_PROGRESS' | 'KEY_REUSED_WITH_DIFFERENT_PAYLOAD';

type RecordRow = {
  request_hash: Buffer;
  state: 'in_progress' | 'completed';
  response_status: number | null;
  response_body: unknown;
};

export function fingerprintRequest(method: string, routeTemplate: string, rawBody: Buffer): Buffer {
  return createHash('sha256').update(`${method} ${routeTemplate}\n`).update(rawBody).digest();
}

export async function claimIdempotencyKey(
  db: SqlClient,
  claim: { principalId: string; key: string; requestHash: Buffer },
): Promise<Result<ClaimOutcome, ClaimError>> {
  const inserted = await db.query<{ principal_id: string }>(
    `INSERT INTO idempotency_records (principal_id, idempotency_key, request_hash, state)
     VALUES ($1, $2, $3, 'in_progress')
     ON CONFLICT (principal_id, idempotency_key) DO NOTHING
     RETURNING principal_id`,
    [claim.principalId, claim.key, claim.requestHash],
  );
  if (inserted.rows.length > 0) return ok({ kind: 'claimed' });

  const existing = await db.query<RecordRow>(
    `SELECT request_hash, state, response_status, response_body
       FROM idempotency_records
      WHERE principal_id = $1 AND idempotency_key = $2`,
    [claim.principalId, claim.key],
  );
  const row = existing.rows[0];
  // The record expired or was released between the two statements; treat as in progress so the
  // client retries instead of the request running twice concurrently.
  if (!row) return err('KEY_IN_PROGRESS');
  if (!row.request_hash.equals(claim.requestHash)) return err('KEY_REUSED_WITH_DIFFERENT_PAYLOAD');
  if (row.state === 'in_progress' || row.response_status === null) return err('KEY_IN_PROGRESS');
  return ok({ kind: 'replay', response: { status: row.response_status, body: row.response_body } });
}
```

Completing and releasing a key:

```sql
-- Completed (inside the business transaction where possible)
UPDATE idempotency_records
   SET state = 'completed', response_status = $3, response_body = $4
 WHERE principal_id = $1 AND idempotency_key = $2;

-- Transient failure: release so the client can retry
DELETE FROM idempotency_records
 WHERE principal_id = $1 AND idempotency_key = $2 AND state = 'in_progress';
```

Map `KEY_IN_PROGRESS` to `409` and `KEY_REUSED_WITH_DIFFERENT_PAYLOAD` to `422`, both as
problem+json with a stable `code`.

## ETags and If-Match

- Derive the ETag from a monotonically increasing `version` column (`"v42"`) or a hash of the
  representation; strong ETags only for byte-identical representations.
- `GET`: if `If-None-Match` matches the current ETag, return `304` with the ETag and no body.
- `PUT`/`PATCH`/`DELETE` on concurrently edited resources:
  - No `If-Match` → `428 Precondition Required`.
  - Apply the change with a conditional update so the check and the write are atomic:

```sql
UPDATE orders
   SET shipping_note = $3, version = version + 1
 WHERE id = $1 AND version = $2
RETURNING version;
```

  - Zero rows updated while the order exists → `412 Precondition Failed`; the client refetches and
    retries. Zero rows and no order (or not visible to the caller) → `404`.
- Return the new ETag on every successful write.
