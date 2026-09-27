# Database Change Management Workflow

This document covers the full lifecycle of database schema and data changes — from planning a change through production deployment and validation.

For planning and executing a specific migration (Expand-Contract, rollback strategy, ORM updates), see the `/migrate` command.
For lifecycle operations, see the `/db` command: `init`, `create <name>`, `dml <name>`, `seed <reference|development|test>`, `status`, `diff`, `audit`.

Lock-safe DDL, per-tool recipes (Flyway, Liquibase, Alembic, Django, Prisma, Drizzle, EF Core, goose, golang-migrate, Atlas, Room, drift, SQLDelight), and CI gates live in the [`db-migrations` skill](../../../.claude/skills/db-migrations/SKILL.md). This guide summarizes the workflow; follow the skill for the details.

---

## Change Classification

Before writing any SQL, classify the change:

| Type | Definition | Risk | Deploy Order |
|---|---|---|---|
| **Additive DDL** | New table, nullable column, column with a constant default, new index | Low | Schema before code |
| **Non-null DDL** | NOT NULL on an existing column, new constraint, foreign key | Medium | Expand-Contract required (`NOT VALID` → `VALIDATE`) |
| **Rename / type change** | Rename a column/table, change a column type | High | Always Expand-Contract — never `RENAME` or `ALTER COLUMN TYPE` on a hot table |
| **Destructive DDL** | DROP table/column | High | Code before schema |
| **DML backfill** | Populate a new column from existing data | Medium | After additive DDL; batched job |
| **DML reference** | Insert/update lookup table data the code depends on | Low | Ships as a migration (or Flyway `R__` repeatable migration) |
| **DML transform** | Restructure or normalize existing data | High | Separate deploy, after code |

---

## Full Lifecycle

```
1. Plan           Classify change. Identify risk. Choose Expand-Contract if needed (/migrate).
       │
       ▼
2. Design         Write target schema. Document rationale. Estimate table sizes.
       │
       ▼
3. Create files   Use /db create <name> or /db dml <name> to scaffold migration files.
       │
       ▼
4. Audit          Run /db audit on new files (and squawk for PostgreSQL). Fix HIGH/MEDIUM issues.
       │
       ▼
5. Test locally   Apply to a local DB. Run application tests. Verify the recovery plan works.
       │
       ▼
6. Code review    Migration files require a separate code review from the application code.
       │
       ▼
7. Staging        Apply to staging. Verify /db status shows no pending. Run smoke tests.
       │
       ▼
8. Production     Apply per the production checklist below. Monitor for 30 minutes.
       │
       ▼
9. Verify         Run /db diff to confirm no schema drift. Close the change ticket.
```

Core rules (from `db-migrations`): migrations are immutable once applied to a shared environment;
recovery is forward-only (a new corrective migration); every deploy is backward compatible;
schema and data changes are separate migrations; no auto-migrate (`prisma db push`,
`drizzle-kit push`, `ddl-auto=update`) outside local development; migrations run once from a
dedicated deploy step, never from every app replica at startup.

---

## Expand-Contract Pattern (Zero-Downtime)

Required for any change that would break existing running code if deployed atomically. `/migrate`
describes it as three phases; the `db-migrations` skill splits the application cut-over into its
own Switch step. Example: replacing `orders.payment_status` with `orders.payment_state`.

### Phase 1 — Expand (PR #1: schema only)
Add the new structure *alongside* the old. Old code continues to work unmodified.

```sql
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Expand: add new column (nullable — old code ignores it; metadata-only, no table rewrite)
ALTER TABLE orders ADD COLUMN payment_state VARCHAR(20);
```

Deploy: schema first → then deploy code that writes to BOTH columns and still reads the old one.

### Phase 2 — Migrate (PR #2: data backfill)
Backfill the new structure from the old in small keyed batches (1k–10k rows), each its own short
transaction, run as a job outside the migration tool's transaction — never one `UPDATE` over the
whole table. Start from the `/db dml <name>` backfill template or the batch loop in `db-migrations`.

```sql
-- One batch; the job repeats it until it updates 0 rows
UPDATE orders SET payment_state = payment_status
WHERE id IN (
  SELECT id FROM orders WHERE payment_state IS NULL ORDER BY id LIMIT 5000
);
```

Then enforce NOT NULL without a blocking scan, in separate migrations:

```sql
ALTER TABLE orders ADD CONSTRAINT orders_payment_state_not_null
  CHECK (payment_state IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_payment_state_not_null;
ALTER TABLE orders ALTER COLUMN payment_state SET NOT NULL;   -- no full scan: the valid CHECK proves it
ALTER TABLE orders DROP CONSTRAINT orders_payment_state_not_null;
```

Deploy: backfill after the dual-writing code is live.

### Phase 3 — Switch (application only)
Deploy code that reads `payment_state`; keep dual-writing until the new path is verified in
production.

### Phase 4 — Contract (PR #3: remove old structure)
Once no running version or consumer (reports, CDC, replicas) uses the old column, stop writing it,
tell the ORM to ignore it, then drop it in a later release.

```sql
SET lock_timeout = '5s';
-- Contract: safe because no deployed code references payment_status anymore
ALTER TABLE orders DROP COLUMN payment_status;
```

Deploy: code removal PR merged and deployed first → then this schema change.

**Never combine Expand and Contract in the same deploy.** Worked recipes for renames, foreign keys,
and type changes: `db-migrations` → `reference/postgres-zero-downtime.md`.

---

## Production Deployment Checklist

### Pre-deployment (at least 1 day before)
- [ ] Migration files reviewed and approved by at least one engineer
- [ ] `/db audit` passed (no HIGH issues); squawk clean for PostgreSQL
- [ ] Migration applied to staging and smoke-tested
- [ ] Row count estimated for affected tables; long migrations rehearsed on production-sized data (lock and duration numbers recorded in the PR)
- [ ] DDL sets `lock_timeout` / `statement_timeout`; indexes on live tables use `CREATE INDEX CONCURRENTLY` in their own non-transactional migration; batch DML confirmed
- [ ] Recovery procedure documented (new corrective migration; a `DOWN` script only where the tool supports it)
- [ ] Destructive changes: verified backup / point-in-time-recovery window and explicit reviewer sign-off
- [ ] DBA review completed for HIGH-risk changes
- [ ] Maintenance window scheduled if downtime is expected

### Deployment sequence
```
For additive DDL (no downtime):
  1. Apply migration from the deploy step (flyway migrate / alembic upgrade head / prisma migrate deploy)
  2. Deploy application code
  3. Verify: /db status shows no pending migrations
  4. Verify: application health endpoint responds 200
  5. Monitor error rate and lock waits for 30 minutes

For destructive DDL (may require downtime):
  1. Deploy application code that no longer uses the old column/table
  2. Wait for all running pods/workers to restart (zero instances using old code)
  3. Apply migration
  4. Verify: /db diff shows no drift
  5. Monitor error rate for 30 minutes
```

If a migration fails on `lock_timeout`, nothing was changed — retry the deploy later rather than
raising the timeout.

### Post-deployment
- [ ] `/db status` — no pending migrations
- [ ] `/db diff` — no schema drift detected
- [ ] Application error rate stable vs. baseline
- [ ] Key query performance verified (check `EXPLAIN (ANALYZE, BUFFERS)` on affected queries; `/perf` if it regressed)
- [ ] Migration recorded in change log (date, version, author, ticket)

---

## Rollback Decision Tree

```
Is the migration already applied to production?
│
├── NO → Run the DOWN migration (if the tool has one) or restore from snapshot
│
└── YES → Write a new FORWARD migration that reverses the change
           │
           ├── Is the change additive (new table/column)?
           │   └── DROP the table/column (safe if no data was written yet)
           │
           ├── Was data written to the new column/table?
           │   └── Assess data loss risk before dropping
           │       ├── Acceptable → DROP with a backup first
           │       └── Not acceptable → Leave the column, revert application code
           │
           └── Was a column/table dropped?
               └── Cannot recover from migration alone
                   └── Restore from snapshot OR recreate and re-backfill from backups
```

---

## Migration File Standards

### Naming
Timestamp prefixes for multi-developer repos; sequential integers only for small, single-branch
repos. `snake_case`, specific verb + object (`add_orders_payment_state`, not `update_orders`).

```
V{timestamp}__{description}.sql           # Flyway (V20260915142000__add_user_preferences.sql)
{timestamp}_{description}.sql             # goose, Atlas
{seq}_{description}.up.sql / .down.sql    # golang-migrate
{seq}.sqm                                 # SQLDelight
```

### Required header comment
```sql
-- Migration: {description}
-- Author:    {name}
-- Date:      {YYYY-MM-DD}
-- Ticket:    {JIRA/Linear/GitHub issue URL}
-- Risk:      Low | Medium | High
-- Estimated rows affected: {N}
-- Rollback:  {procedure or "New corrective migration V{N+1}__revert_..."}
```

### Structural requirements
- Every migration must be idempotent where possible (`IF NOT EXISTS`, `IF EXISTS`, `ON CONFLICT`)
- Every migration must include a verification query: `-- Verify: SELECT COUNT(*) FROM ...`
- DDL migrations start with `SET lock_timeout` and `SET statement_timeout`
- DML migrations must be batched for tables > 100,000 rows
- `CREATE INDEX` on any table with live traffic must use `CONCURRENTLY` (`/db audit` flags tables > 10,000 rows), alone in a migration that runs outside a transaction — see the per-tool table in `db-migrations`
- No `TRUNCATE` without explicit DBA approval and a backup step
- Credentials never appear in migration files or committed config; use separate migration (DDL) and application (DML) roles

---

## CI/CD Integration

On every pull request that touches migrations, CI should:

1. **Lint** new migrations (squawk for PostgreSQL; strong_migrations for Rails; `atlas migrate lint` with Atlas Pro)
2. **Apply** the full history to a fresh, throwaway database matching the production major version
3. **Assert** no pending, failed, or ignored migrations using machine-readable output (never grep human text)
4. **Diff models against migrations** to catch forgotten migrations (`alembic check`, `dotnet ef migrations has-pending-model-changes`, `prisma migrate diff ... --exit-code`, …)
5. **Run integration tests** against the migrated database

Skeleton (PostgreSQL; a complete Flyway workflow is in `db-migrations` → `reference/ci.md`):

```yaml
# .github/workflows/migrations.yml
permissions:
  contents: read

jobs:
  database:
    runs-on: ubuntu-24.04
    services:
      postgres:
        image: postgres:18.6
        env:
          POSTGRES_DB: app
          POSTGRES_USER: ci
          POSTGRES_PASSWORD: ci-throwaway   # ephemeral container, not a secret
        ports: ["5432:5432"]
        options: --health-cmd "pg_isready -U ci -d app" --health-interval 5s --health-retries 10
    env:
      DATABASE_URL: postgres://ci:ci-throwaway@localhost:5432/app
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Lint migrations
        run: npx --yes squawk-cli@2.66.0 --pg-version=18 db/migrations/*.sql

      - name: Apply migrations
        # Replace with your tool's apply command:
        #   Flyway:         flyway migrate
        #   Alembic:        alembic upgrade head
        #   Prisma:         prisma migrate deploy
        #   Drizzle:        drizzle-kit migrate
        #   goose:          goose -dir ./db/migrations postgres "$DATABASE_URL" up
        #   golang-migrate: migrate -path ./db/migrations -database "$DATABASE_URL" up
        #   EF Core:        ./efbundle --connection "$DATABASE_URL"
        run: <your tool's apply command>

      - name: Assert no pending migrations
        # Must exit non-zero on pending/failed migrations, e.g.
        #   prisma migrate status   |   flyway info -outputType=json | jq -e '...'
        run: <your tool's machine-checkable status command>

      - name: Run tests against migrated DB
        run: <your integration test command>
```

Pull-request CI only talks to databases it creates. Production drift detection is a separate
scheduled job inside the production network, using a read-only role against a replica — never
put production credentials into PR CI.

---

## Seed Data Workflow

Seed data is separate from migrations. It is applied on top of an initialized schema
(`/db seed <reference|development|test>` generates the scripts).

```
db/seeds/
├── reference/     → Lookup/config data, all environments (idempotent upserts)
│   ├── subscription_plans.sql
│   └── country_codes.sql
├── development/   → Applied in local/dev environments only (fake data)
│   └── sample_orders.sql
└── test/          → Applied before automated tests (minimal, deterministic)
    └── test_fixtures.sql
```

### Applying seeds
```bash
# PostgreSQL (all tools)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/seeds/reference/subscription_plans.sql

# Django
python manage.py loaddata reference_data

# Prisma (seed command configured in prisma.config.ts, e.g. "tsx prisma/seed.ts")
npx prisma db seed

# EF Core
dotnet run --project src/Seeder
```

### Rules
- Reference seeds: idempotent (`ON CONFLICT ... DO NOTHING` or `DO UPDATE`)
- Reference data the application cannot run without ships as a migration (or Flyway `R__`), not as an optional seed
- Development/test seeds: reset-safe (DELETE all rows before inserting, or use transactions)
- Never apply development seeds to production; never seed real personal data — generate fakes
- Commit seed files alongside the migration that creates the seeded table

---

## Schema Drift Response

If `/db diff` detects drift:

| Finding | Likely cause | Action |
|---|---|---|
| Table in DB not in migrations | Manual table created in prod | Create migration to drop it, or add it to migrations |
| Column in DB not in migrations | Manual column added in prod | Add to migrations or document as technical debt |
| Index missing in DB | Migration failed silently, or an `INVALID` index from a failed concurrent build | Drop the invalid index and re-apply, or create a fix migration |
| Table in migrations not in DB | Migration never applied | Apply pending migrations immediately |
| Constraint mismatch | Manual ALTER in prod | Create corrective migration |

**Never manually modify production schema** — all changes must go through migrations. If an emergency manual change was made, immediately create a migration that documents it.

---

## Tool Quick Reference

| Operation | Flyway | Alembic | Prisma | Drizzle | goose | EF Core |
|---|---|---|---|---|---|---|
| Apply all | `flyway migrate` | `alembic upgrade head` | `prisma migrate deploy` | `drizzle-kit migrate` | `goose up` | `dotnet ef database update` (production: migration bundle `efbundle`) |
| Status | `flyway info` | `alembic current` | `prisma migrate status` | — | `goose status` | `dotnet ef migrations list` |
| New migration | `V{timestamp}__name.sql` | `alembic revision -m "name"` | `prisma migrate dev --name name` | `drizzle-kit generate --name name` | `goose create name sql` | `dotnet ef migrations add Name` |
| Rollback | Forward fix (undo is a paid feature) | `alembic downgrade -1` | Forward fix; `prisma migrate resolve --rolled-back <name>` for a failed migration | Forward fix | `goose down` | `dotnet ef database update PreviousMigration` |
| Models vs. migrations / validate | `flyway validate` | `alembic check` | `prisma migrate diff ... --exit-code` | `drizzle-kit check` | `goose validate` | `dotnet ef migrations has-pending-model-changes` |

goose commands take the directory, driver, and connection (`goose -dir ./db/migrations postgres "$DATABASE_URL" up`). Liquibase, Django, golang-migrate, Atlas, and mobile tools: see the `db-migrations` references.
