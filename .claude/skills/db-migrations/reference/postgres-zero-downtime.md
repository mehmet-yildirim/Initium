# PostgreSQL zero-downtime recipes

Each numbered step is a separate migration (and usually a separate deploy). Start every DDL
migration with `SET lock_timeout` / `SET statement_timeout` as described in `SKILL.md`.

## Add an index to a live table

```sql
-- V12__orders_payment_status_idx.sql   (non-transactional migration, statement alone in file)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_payment_status
    ON orders (payment_status)
    WHERE payment_status <> 'paid';
```

If the build fails, the index stays `INVALID`. Find and drop it before retrying:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_payment_status;
```

## Add a column with a CHECK

```sql
-- 1. Expand: constant default is metadata-only on PostgreSQL 11+
SET lock_timeout = '5s';
ALTER TABLE orders ADD COLUMN payment_status varchar(20) NOT NULL DEFAULT 'pending';
ALTER TABLE orders ADD CONSTRAINT chk_orders_payment_status
    CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')) NOT VALID;

-- 2. Validate (separate migration): scans without blocking writes
ALTER TABLE orders VALIDATE CONSTRAINT chk_orders_payment_status;
```

## Make an existing column NOT NULL

```sql
-- 1. Backfill NULLs with a batched job first (see SKILL.md)
-- 2.
SET lock_timeout = '5s';
ALTER TABLE users ADD CONSTRAINT chk_users_email_not_null CHECK (email IS NOT NULL) NOT VALID;
-- 3.
ALTER TABLE users VALIDATE CONSTRAINT chk_users_email_not_null;
-- 4. PostgreSQL 12+ uses the valid CHECK to skip the full-table scan
SET lock_timeout = '5s';
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users DROP CONSTRAINT chk_users_email_not_null;
```

## Add a foreign key

```sql
-- 1. Index the referencing column first (non-transactional migration)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);
-- 2.
SET lock_timeout = '5s';
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
-- 3.
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_customer;
```

## Add a unique constraint

```sql
-- 1. (non-transactional)
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_users_email_idx ON users (email);
-- 2. Instant: reuses the index
SET lock_timeout = '5s';
ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE USING INDEX uq_users_email_idx;
```

## Rename a column (expand/contract)

1. **Expand:** `ALTER TABLE users ADD COLUMN full_name text;`
2. **Dual-write:** deploy code that writes both `name` and `full_name` and still reads `name`.
3. **Backfill:** batched job `UPDATE ... SET full_name = name WHERE full_name IS NULL`.
4. **Switch reads:** deploy code that reads `full_name` (still dual-writes).
5. **Stop writing** `name`; mark it ignored in the ORM.
6. **Contract:** a later release runs `ALTER TABLE users DROP COLUMN name;`

A trigger can replace step 2 when not every writer can be changed at once; drop it in step 6.

## Change a column type

Same shape as a rename: add `amount_cents bigint`, dual-write, batched backfill with the
conversion, validate any new constraints, switch reads, drop the old column. In-place type
changes that avoid a rewrite (increasing `varchar(n)` length, `varchar(n)` → `text`) are safe
to run directly with a `lock_timeout`.

## Replace a soft-delete flag

```sql
-- 1. Expand
ALTER TABLE users ADD COLUMN deleted_at timestamptz;
-- 2. Batched backfill job: SET deleted_at = updated_at WHERE is_deleted AND deleted_at IS NULL
-- 3. Contract, after no code reads is_deleted
ALTER TABLE users DROP COLUMN is_deleted;
```

## Drop a table

1. Deploy code that no longer reads or writes it; confirm with `pg_stat_user_tables`
   (`seq_scan`, `idx_scan`, `n_tup_ins` stop increasing).
2. Optionally `ALTER TABLE old_table RENAME TO old_table_deprecated` for one release as a canary.
3. `DROP TABLE old_table_deprecated;` after the backup/PITR window covers the rename.
