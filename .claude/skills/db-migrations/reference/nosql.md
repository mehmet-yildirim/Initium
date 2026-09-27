# NoSQL schema evolution

Document and key-value stores have no DDL, so the schema lives in application code. The same
expand/contract discipline applies: readers must tolerate both shapes during a rollout.

## General rules

- Version the shape: store `schemaVersion` on documents/items and branch on it in the adapter
  that maps storage records to domain objects — never in domain code.
- Read old + new, write new ("lazy migration"); backfill the long tail with a batched,
  resumable, idempotent job that records a checkpoint.
- Validate on write with a schema (Zod, Pydantic, JSON Schema) at the adapter boundary.

## MongoDB

Use a migration runner (`migrate-mongo`, or `umzug` with a MongoDB storage) so index and
validator changes are versioned like SQL migrations.

```javascript
// migrations/20260915142000-add-user-prefs-index.js  (migrate-mongo)
module.exports = {
  async up(db) {
    await db.collection("users").createIndex(
      { "preferences.key": 1 },
      { name: "idx_users_prefs_key", sparse: true },
    );
  },
  async down(db) {
    await db.collection("users").dropIndex("idx_users_prefs_key");
  },
};
```

- Index builds on large collections still consume resources; schedule them and watch replica lag.
- Add `$jsonSchema` validators with `validationLevel: "moderate"` first (existing invalid
  documents are tolerated), then tighten to `"strict"` after the backfill.

## DynamoDB

- New attributes need no migration; readers treat them as optional.
- Removing or renaming: deploy code that writes the new attribute and reads both → backfill
  with a segmented, rate-limited `Scan` + conditional `UpdateItem` → switch reads → stop
  writing the old attribute → remove it.
- New access patterns need a GSI; create it, wait for `ACTIVE`, then deploy code that queries it.

## Redis

- Put the format version in the key (`user:v2:{id}:session`) or in the value envelope.
- Deploy code that reads v2 and falls back to v1, writes v2; let v1 keys expire via TTL
  instead of mass deletion (`SCAN` + `UNLINK` in small batches if you must delete).
