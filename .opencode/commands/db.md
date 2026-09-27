Database change management operations — initialization, migration scaffolding, DML changes, seed data, schema drift detection, and audit.

This command complements `/migrate` (which plans and executes a specific migration).
Use `/db` for lifecycle management: setting up tooling, scaffolding files, checking state, managing seeds.

---

## Subcommands

| Subcommand | What it does |
|---|---|
| `db init` | Bootstrap migration infrastructure for the detected stack |
| `db create <name>` | Scaffold a new DDL migration file with proper naming and sequencing |
| `db dml <name>` | Scaffold a DML data migration (backfill, reference data, data transform) |
| `db seed <env>` | Generate or apply seed data for the specified environment |
| `db status` | Show pending migrations and current schema version |
| `db diff` | Detect schema drift between expected (migrations) and actual (database) |
| `db audit` | Review recent migration files for safety issues before deployment |

---

## Step 1: Detect Context

Read the following before taking any action:
- `AGENTS.md` — primary language, framework, database
- `agent.config.yaml` or `.project-config.yaml` — project type
- Directory structure — detect which migration tool is already in use:
  - `flyway.conf` or `db/migration/V*.sql` → Flyway
  - `alembic.ini` or `alembic/` → Alembic
  - `manage.py` + `*/migrations/*.py` → Django Migrations
  - `prisma/schema.prisma` → Prisma Migrate
  - `drizzle.config.*` → Drizzle
  - `db/migrations/*.sql` with `-- +goose` markers → Goose
  - `db/migrations/*.[0-9]*.up.sql` → golang-migrate
  - `atlas.hcl` → Atlas
  - `Migrations/*.cs` in .NET project → EF Core
  - `DatabaseVersion` or `@Database(version=...)` → Room
  - `lib/database/*.dart` with `MigrationStrategy` → drift
  - `*.sqm` files → SQLDelight

State: "Detected stack: [stack]. Migration tool: [tool]. Current migration count: [N]. Highest version: [version]."

---

## `db init` — Bootstrap migration infrastructure

Set up the migration tool for a project that doesn't have one yet.

### Detect the right tool from the stack:

| Stack | Default tool | Setup command |
|---|---|---|
| Java / Spring Boot | Flyway | `mvn flyway:info` (add `flyway-core` dependency) |
| Python + SQLAlchemy | Alembic | `pip install alembic && alembic init alembic` |
| Python + Django | Built-in | `python manage.py makemigrations` |
| TypeScript (Prisma) | Prisma Migrate | `npx prisma init` |
| TypeScript (Drizzle) | Drizzle | `bun add drizzle-kit && drizzle-kit init` |
| Go | Goose | `go get github.com/pressly/goose/v3` |
| .NET / EF Core | EF Core | `dotnet add package Microsoft.EntityFrameworkCore.Design` |
| Android | Room (built-in) | Add `exportSchema = true` to `@Database` |
| Flutter | drift (built-in) | `dart run drift_dev schema dump ...` |
| KMP | SQLDelight (built-in) | Add `verifyMigrations = true` to `build.gradle.kts` |

### Output:
1. The exact commands to run to initialize the tool
2. The directory structure that will be created
3. Any configuration file snippets needed
4. A checklist of what to configure before running the first migration:
   - Database URL connection variable name
   - Migration directory path
   - Schema history table name (if customizable)
   - CI/CD integration step

---

## `db create <name>` — Scaffold a new DDL migration

Create a properly named, numbered DDL migration file ready to fill in.

### Steps:
1. Determine the next version number:
   - Flyway: next `V{N}` or timestamp `V{YYYYMMDDHHmmss}`
   - Alembic: `alembic revision -m "{name}"` (generates hash-based revision ID)
   - Goose: `goose create {name} sql`
   - golang-migrate: next zero-padded integer, e.g., `000043`
   - EF Core: `dotnet ef migrations add {PascalCaseName}`
   - Room: increment `@Database(version = N+1)` and create `Migration(N, N+1)` object
   - SQLDelight: next integer `.sqm` file

2. Generate the scaffolded file with:
   - Header comment: what this migration does, JIRA/Linear ticket if known
   - `Up` section (empty or with ALTER TABLE skeleton matching the description)
   - `Down` section (rollback — even for forward-only tooling, document what the rollback would be)
   - A TODO comment: "Review for lock impact on large tables"

3. Check for naming conflicts with existing migration files

4. Report: "Created migration file: [path]. Next step: fill in the SQL, then test with `/migrate`."

---

## `db dml <name>` — Scaffold a DML data migration

Data migrations change rows, not schema. They need different patterns than DDL migrations.

### Determine migration type from the description:
- **Backfill** — populate a new column from existing data
- **Reference data** — insert/update lookup table records
- **Data transform** — restructure or normalize existing data
- **Cleanup** — remove orphaned records, soft-deleted rows, etc.

### Generate the appropriate scaffold:

**Backfill template:**
```sql
-- Backfill: {description}
-- Idempotent: safe to run multiple times
-- Batch size: 1000 rows to minimize lock pressure
-- Ticket: {ticket-id if known}

DO $$
DECLARE
  batch_size  INT := 1000;
  processed   INT;
  total       INT;
BEGIN
  SELECT COUNT(*) INTO total FROM {table} WHERE {condition_to_fill};
  RAISE NOTICE 'Total rows to process: %', total;

  LOOP
    UPDATE {table}
    SET    {new_column} = {expression_from_existing_data}
    WHERE  id IN (
      SELECT id FROM {table}
      WHERE  {new_column} IS NULL  -- idempotency guard
      LIMIT  batch_size
    );

    GET DIAGNOSTICS processed = ROW_COUNT;
    EXIT WHEN processed = 0;
    RAISE NOTICE 'Processed % rows', processed;
    PERFORM pg_sleep(0.1);  -- reduce lock pressure
  END LOOP;
  RAISE NOTICE 'Backfill complete.';
END $$;
```

**Reference data template:**
```sql
-- Reference data: {description}
-- Idempotent: ON CONFLICT DO NOTHING ensures safe re-runs
INSERT INTO {table} ({columns}) VALUES
    ({row1}),
    ({row2})
ON CONFLICT ({pk_column}) DO NOTHING;
```

**Data transform template:**
```sql
-- Transform: {description}
-- Pre-condition: verify before running
-- SELECT COUNT(*) FROM {table} WHERE {old_format_condition};
BEGIN;
  -- Step 1: verify no unexpected data
  DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM {table} WHERE {unexpected_condition}) THEN
      RAISE EXCEPTION 'Unexpected data found — review before proceeding';
    END IF;
  END $$;

  -- Step 2: transform
  UPDATE {table} SET {new_column} = {transform}({old_column});

  -- Step 3: verify result
  -- SELECT COUNT(*) FROM {table} WHERE {new_column} IS NULL;
COMMIT;
```

### Additional guidance:
- Verify the DML migration on a copy of production data before the real deploy
- Always include a "how to verify success" query in the migration file
- Deploy DML migrations in a separate step from DDL migrations (easier to monitor and roll back)

---

## `db seed <env>` — Manage seed data

Seed data is NOT a migration — it is reference or development data applied on top of an initialized schema.

### Environments:
- `db seed reference` — lookup tables, enums, configuration (all environments, idempotent)
- `db seed development` — realistic fake data for local development
- `db seed test` — minimal, deterministic data for automated tests

### Generate seed script:
1. Identify the target tables from context (reference tables, initial config)
2. Generate an idempotent SQL seed file in `db/seeds/{env}/`
3. Use `ON CONFLICT ... DO UPDATE` for reference data that may evolve
4. Use `ON CONFLICT ... DO NOTHING` for append-only seed data

### Report:
- The seed file path
- How to run it for the detected tool
- Whether it is safe to run on production (reference seeds only)

---

## `db status` — Check migration state

Show what migrations are applied, pending, and how the current schema compares to the codebase.

### Commands per tool:
```bash
# Flyway
flyway -url=$DATABASE_URL info

# Alembic
alembic current
alembic history --verbose

# Prisma
prisma migrate status

# Goose
goose -dir ./db/migrations postgres "$DATABASE_URL" status

# golang-migrate
migrate -path ./db/migrations -database "$DATABASE_URL" version

# EF Core
dotnet ef migrations list
```

### Output format:
```
Migration Status
════════════════════════════════════════════════
Applied:
  ✅ V1__initial_schema.sql        (2024-01-15 09:00:00)
  ✅ V2__add_user_preferences.sql  (2024-02-01 14:30:00)

Pending:
  ⏳ V3__add_payment_status.sql    (NOT YET APPLIED)

Current schema version: V2
Pending count:          1
════════════════════════════════════════════════
```

Warn if any migration is in "failed" or "out of order" state.

---

## `db diff` — Schema drift detection

Detect differences between the expected schema (what migrations produce) and the actual database.

### Method:
1. Apply all migrations to a fresh temporary database
2. Dump the schema of both the fresh DB and the target DB
3. Diff the two schemas

### Commands:
```bash
# Atlas (recommended)
atlas schema diff \
  --from "postgres://user:pass@localhost/migrated_fresh" \
  --to   "postgres://user:pass@prod-host/appdb"

# PostgreSQL manual diff
pg_dump --schema-only $FRESH_DB_URL   | sort > fresh.sql
pg_dump --schema-only $TARGET_DB_URL  | sort > target.sql
diff fresh.sql target.sql

# Flyway repair
flyway -url=$DATABASE_URL repair    # Fix checksum mismatches
flyway -url=$DATABASE_URL validate  # Check for divergence
```

### Report format:
```
Schema Drift Report
════════════════════════════════════════════════
Tables in DB not in migrations:
  ⚠️  temp_import_cache  (likely manual — should be dropped or added to migrations)

Columns in DB but not in migrations:
  ⚠️  orders.internal_notes  (manually added — risk: auto-dropped by future migration)

Indexes missing from DB:
  ❌ idx_users_email  (expected but absent — query performance risk)
════════════════════════════════════════════════
Recommendation: [list of corrective actions]
```

---

## `db audit` — Migration safety review

Review pending or recent migration files for common issues before deployment.

### Check each migration file for:

**High risk (block deployment):**
- [ ] `DROP TABLE` or `DROP COLUMN` without a prior deploy removing all code references
- [ ] `ALTER TABLE ... ADD COLUMN ... NOT NULL` without a default value (table lock on large tables)
- [ ] Missing `IF EXISTS` / `IF NOT EXISTS` guards (migration fails on re-run)
- [ ] Unbatched `UPDATE` affecting more than an estimated 10,000 rows (lock contention)
- [ ] Any `TRUNCATE` (irreversible data loss)
- [ ] `RENAME COLUMN` or `RENAME TABLE` (breaks all ORM/query code referencing the old name)

**Medium risk (review required):**
- [ ] `CREATE INDEX` without `CONCURRENTLY` on a table with > 10,000 rows (blocks writes)
- [ ] Missing rollback / down migration
- [ ] DML + DDL combined in one migration (split them)
- [ ] Non-idempotent DML (can fail on re-run)

**Good practices (informational):**
- [ ] Header comment describes what and why
- [ ] JIRA/Linear ticket linked
- [ ] "How to verify success" query included
- [ ] Estimated execution time noted for large operations

### Output:
```
Migration Audit: V42__add_payment_status.sql
════════════════════════════════════════════════
[HIGH]   Line 3: ADD COLUMN NOT NULL without default — will lock table
         Fix: Add DEFAULT value, or use two migrations (add nullable, backfill, add constraint)

[MEDIUM] No down/rollback migration provided
         Fix: Add a undo migration or document the recovery procedure

[INFO]   No JIRA ticket in header comment
════════════════════════════════════════════════
Verdict: BLOCK — fix HIGH issues before deploying to staging or production.
```

---

## Step 3: Final Output

After any subcommand, provide:
1. The generated file(s) or command output
2. The next action in the workflow:
   - For `db create` / `db dml`: fill in the TODO sections, then use `/migrate` to plan the execution
   - For `db status` / `db diff`: list corrective actions
   - For `db audit`: list issues and their fixes

---

Operation: $ARGUMENTS
(Format: `<subcommand> [name/env]` — e.g., `create add_user_preferences`, `dml backfill_order_totals`, `seed reference`, `status`, `diff`, `audit`)
