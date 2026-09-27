---
name: db-migrations
description: Database change management for PostgreSQL 18 and other stores — zero-downtime expand/contract, lock-safe DDL (lock_timeout, CREATE INDEX CONCURRENTLY, NOT VALID + VALIDATE CONSTRAINT), batched backfills, seed data, drift detection, and migration linting with squawk, Atlas and strong_migrations. Tool recipes for Flyway 13, Liquibase 5, Alembic, Django, Prisma 7, Drizzle, EF Core 10, goose, golang-migrate, Room, drift and SQLDelight. Use when writing, reviewing or running schema/data migrations, wiring migration CI gates, or diagnosing schema drift.
globs:
  - "**/migrations/**"
  - "**/migration/**"
  - "**/Migrations/**"
  - "**/alembic/**"
  - "**/flyway/**"
  - "**/liquibase/**"
  - "**/db/changelog/**"
  - "**/V[0-9]*__*.sql"
  - "**/R__*.sql"
  - "**/*.sql.conf"
  - "**/*.sqm"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Database Change Management

Universal rules for changing schemas and data safely. Per-tool commands and examples live in
`reference/`; data-access code (repositories, pooling, transactions) is out of scope.

## Baseline (September 2026)

- PostgreSQL 18 (18.6) is the default target; 17 remains supported. PostgreSQL 19 is in beta
  (GA targeted for late October 2026) — test against it, do not run production on it before GA.
- Flyway 13.8, Liquibase 5.0, Alembic 1.20, Django 6.1, Prisma ORM 7.10 (8.0 is a release
  candidate — do not adopt before GA), Drizzle ORM 0.45 / drizzle-kit 0.31 (1.0 is in RC),
  EF Core 10, goose 3.28, golang-migrate 4.20, Atlas 1.3.
- Linters: squawk 2.66 (PostgreSQL), strong_migrations 2.8 (Rails), `atlas migrate lint`
  (Atlas Pro since v0.38; basic analyzers in the Apache-2.0 Community Edition).

## Core principles

1. **Immutable once shared.** Never edit a migration applied to any shared environment; add a
   new one. Keep checksum validation on (Flyway, Liquibase, Alembic revision graph).
2. **Forward-only recovery.** Down scripts are a convenience; the recovery plan is a new
   corrective migration.
3. **Every deploy is backward compatible.** Old and new application versions run side by side
   during a rollout, so each migration must work with both (see expand/contract below).
4. **Schema changes and data changes are separate migrations.** Never mix long-running DML
   with DDL in one transaction.
5. **No auto-migrate in production.** `ddl-auto=update`, `AutoMigrate()`, `EnsureCreated()`,
   `drizzle-kit push`, `prisma db push` are for local development only.
6. **Migrations run once, from one place.** A dedicated deploy step or job applies them before
   the new app version rolls out — never from every app replica at startup in production.

## Naming

- Timestamp prefixes for multi-developer repos (`20260915142000_add_user_preferences.sql`,
  Flyway `V20260915142000__add_user_preferences.sql`); sequential integers only for small,
  single-branch repos.
- `snake_case`, specific verb + object (`add_orders_payment_status`, not `update_orders`);
  include the ticket id when the team tracks one. No spaces, no uppercase.

## Zero-downtime: expand/contract

Split every breaking change into releases that each keep old and new code working.

| Phase | Schema change | Application change |
|---|---|---|
| Expand | Add new column/table/index (nullable or with a constant default) | Old code ignores it |
| Migrate | Batched backfill; add constraints as `NOT VALID`, then validate | Dual-write old + new; read old |
| Switch | — | Read new; keep dual-writing until verified |
| Contract | Drop old column/table/trigger in a later release | Stop writing old |

- Renames and type changes are always expand/contract (new column + backfill + switch + drop),
  never `RENAME COLUMN` or `ALTER COLUMN TYPE` on a hot table.
- Drop only after every running version and every consumer (reports, CDC, replicas) stopped
  using the object. Tell ORMs to ignore the column first (e.g. EF `[NotMapped]`, Rails
  `ignored_columns`) so cached statements do not break.
- Worked recipes (rename, NOT NULL, foreign key, type change): `reference/postgres-zero-downtime.md`.

## Lock safety (PostgreSQL)

- Start every DDL migration with timeouts so a blocked lock fails fast instead of queueing all
  traffic behind it; retry the deploy later:

  ```sql
  SET lock_timeout = '5s';
  SET statement_timeout = '60s';
  ```

  Use `SET LOCAL` inside an explicit transaction. Raise `statement_timeout` (or set `0`) only
  for `CONCURRENTLY` builds and `VALIDATE CONSTRAINT`, which take weak locks.
- **Indexes:** `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY` / `REINDEX ... CONCURRENTLY`
  on any table with traffic. They cannot run inside a transaction block: put each one alone
  in its own non-transactional migration (mechanism per tool in the table below). A failed
  concurrent build leaves an `INVALID` index — drop it and retry; use `IF NOT EXISTS` so
  retries are idempotent.
- **Constraints:** add `CHECK` and `FOREIGN KEY` constraints with `NOT VALID` (brief lock, no
  scan), then `ALTER TABLE ... VALIDATE CONSTRAINT` in a separate migration (weaker lock, scans
  without blocking writes).
- **NOT NULL on an existing column:** add `CHECK (col IS NOT NULL) NOT VALID`, validate it, then
  `SET NOT NULL` (PostgreSQL 12+ skips the full scan when a valid check proves it), then drop
  the check.
- **Unique constraints:** `CREATE UNIQUE INDEX CONCURRENTLY`, then
  `ADD CONSTRAINT ... UNIQUE USING INDEX`.
- **Columns:** `ADD COLUMN` with no default or a constant default is metadata-only; volatile
  defaults (`now()`, `gen_random_uuid()`) and most type changes rewrite the table.
- Never `VACUUM FULL`, `CLUSTER`, or `LOCK TABLE` in a migration against a live table.

| Tool | Run one migration outside a transaction |
|---|---|
| Flyway | `V7__x.sql.conf` with `executeInTransaction=false` **and** `postgresql.transactional.lock=false` (otherwise Flyway's advisory lock deadlocks the build) |
| Liquibase | `runInTransaction="false"` on the changeset |
| Alembic | `with op.get_context().autocommit_block():` |
| Django | `atomic = False` on the migration + `AddIndexConcurrently` |
| Prisma | One statement per `migration.sql` (multi-statement files run in one implicit transaction) |
| goose | `-- +goose NO TRANSACTION` |
| golang-migrate | One statement per file |
| EF Core | `migrationBuilder.Sql(sql, suppressTransaction: true)` |

Per-tool details: see the reference files listed at the end.

## Data migrations and backfills

- Idempotent: safe to re-run after a partial failure (`WHERE new_col IS NULL`,
  `ON CONFLICT DO NOTHING`/`DO UPDATE`).
- Batched: small keyed batches (1k–10k rows), each its own short transaction, with a pause
  between batches to let replicas and autovacuum keep up. Never one `UPDATE` over a large table.
- Run large backfills as a job (application command, worker, or script) outside the migration
  tool's transaction; the migration only adds the column and later the constraint.
- Every batch must make progress: rows that cannot be filled must be marked or excluded, or the
  loop never ends.

```sql
-- backfill_order_totals_batch.sql — returns the number of rows updated
WITH batch AS (
  SELECT id FROM orders
  WHERE total_cents IS NULL
  ORDER BY id
  LIMIT 5000
  FOR UPDATE SKIP LOCKED
),
totals AS (
  SELECT b.id, COALESCE(SUM(li.quantity * li.unit_price_cents), 0) AS total_cents
  FROM batch b
  LEFT JOIN line_items li ON li.order_id = b.id
  GROUP BY b.id
),
updated AS (
  UPDATE orders o SET total_cents = t.total_cents
  FROM totals t
  WHERE o.id = t.id
  RETURNING 1
)
SELECT count(*) FROM updated;
```

```bash
# Each psql call is its own transaction; stop when a batch updates nothing.
set -euo pipefail
while :; do
  updated=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qtA -f backfill_order_totals_batch.sql)
  echo "{\"event\":\"backfill_batch\",\"table\":\"orders\",\"updated\":$updated}"
  [ "$updated" -eq 0 ] && break
  sleep 0.5
done
```

## Seed data

- Separate `seeds/reference/` (lookup data, all environments, idempotent upserts),
  `seeds/development/` (fake data), and `seeds/test/` (minimal, deterministic).
- Reference data that the code depends on ships as a migration (or Flyway `R__` repeatable
  migration), not as an optional seed.
- Never seed real personal data; generate fakes.

## Toolchain and CI gates

Run on every pull request that touches migrations (full workflow: `reference/ci.md`):

1. **Lint** the new migrations: squawk for PostgreSQL SQL files (keep
   `require-concurrent-index-creation`, `constraint-missing-not-valid`, `require-lock-timeout`
   enabled),
   `atlas migrate lint` if you have Atlas Pro, strong_migrations for Rails.
2. **Apply** all migrations to a fresh ephemeral database (service container / Testcontainers)
   matching the production major version.
3. **Assert no pending, failed or ignored migrations** using machine-readable output — never
   grep human text (e.g. `flyway info -outputType=json | jq -e ...`).
4. **Diff models against migrations** (ORM schema vs. migration-produced schema) and fail on
   differences — catches forgotten migrations.
5. **Run the application's integration tests** against the migrated database.

Drift against production is a separate scheduled job that runs inside the production network
with a read-only role against a replica. Never put production credentials or production
connection strings into pull-request CI.

## Security

- Credentials come from the environment or a secrets manager; never in migration files,
  config committed to git, or command lines that end up in logs.
- Separate roles: a migration role with DDL rights on the application schema only, and an
  application role with DML only. Neither is a superuser. Drift jobs use a read-only role.
- `GRANT`/`REVOKE` and row-level security policies are part of migrations and reviewed like code.
- Review DML migrations for data exfiltration or mass deletion (`INSERT INTO ... SELECT * FROM
  users`, `DELETE` without `WHERE`).
- Destructive migrations (drop, truncate) require a verified backup / point-in-time-recovery
  window and explicit reviewer sign-off.

## Observability

- Migration runners emit structured logs (version, description, duration, outcome) and the
  deploy pipeline records which version is applied per environment.
- Turn on `log_lock_waits` and alert on lock waits and long transactions during deploys.
- Backfill jobs log progress per batch (as above) and export rows-remaining as a metric.

## Testing

- CI applies the full history on an empty database and, for large systems, from a restored
  anonymised production snapshot to catch data-dependent failures.
- Test data migrations with fixtures that include edge cases (NULLs, orphans, duplicates).
- Mobile: Room `MigrationTestHelper`, drift `SchemaVerifier`, SQLDelight `verifyMigrations`.
- Rehearse long migrations on production-sized data and record lock and duration numbers in
  the pull request.

## Reference files

- `reference/postgres-zero-downtime.md` — read when renaming columns, adding NOT NULL / foreign
  keys, or changing types on live PostgreSQL tables.
- `reference/flyway-liquibase.md` — read when working on Java/Spring Boot migrations.
- `reference/alembic-django.md` — read when working on Python migrations.
- `reference/prisma-drizzle.md` — read when working on Prisma 7 or Drizzle migrations.
- `reference/go-tools.md` — read when using goose, golang-migrate or Atlas.
- `reference/efcore.md` — read when working on .NET EF Core migrations.
- `reference/mobile.md` — read when working on Room, drift or SQLDelight schema versions.
- `reference/nosql.md` — read when evolving MongoDB, DynamoDB or Redis data shapes.
- `reference/ci.md` — read when wiring migration linting, apply checks and drift detection in CI.

_Versions verified September 2026._
