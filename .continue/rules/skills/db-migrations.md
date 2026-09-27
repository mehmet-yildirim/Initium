---
name: db-migrations
description: Database change management — DDL/DML migrations, schema versioning, seed data, drift detection. Covers Flyway, Liquibase, Alembic, Prisma Migrate, Drizzle, EF Core, Goose, golang-migrate, Atlas, Room, SQLDelight, drift. Use when writing or reviewing schema migrations, seed data, or diagnosing schema drift.
globs:
  - "**/migrations/**"
  - "**/db/migrations/**"
  - "**/alembic/**"
  - "**/*.sql"
  - "**/flyway/**"
  - "**/liquibase/**"
  - "**/schema.prisma"
  - "**/drizzle.config.*"
  - "**/*.migration.ts"
  - "**/*_migration*.go"
  - "**/*.sqm"
  - "**/V[0-9]*__*.sql"
  - "**/R__*.sql"
  - "**/*Migration*.cs"
  - "**/*Migrations*.cs"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Database Change Management Standards

## Core Principles

1. **Migrations are immutable** — once applied to any shared environment, never edit a migration file. Create a new one instead.
2. **Forward-only by default** — rollback scripts are good to have but the primary recovery plan is always a new corrective migration.
3. **Schema before code in additive changes** — deploy the migration first so old code remains compatible with the new schema.
4. **Code before schema in destructive changes** — deploy code that no longer uses the old column/table, then drop it in a subsequent deploy.
5. **Never auto-migrate in production** — `spring.jpa.hibernate.ddl-auto=update`, `db.AutoMigrate()`, `Ensure-Created` are development conveniences only.

---

## Migration Naming Conventions

### Timestamp-based (preferred for distributed teams)
```
20240315142000_add_user_preferences.sql
20240315142000_add_user_preferences.go       # Goose
V20240315142000__add_user_preferences.sql    # Flyway
```

### Sequential integer (preferred for single-repo teams)
```
0001_initial_schema.sql
0042_add_user_preferences.sql
```

### Rules
- Use `snake_case` for the description
- Be specific: `add_user_preferences` not `update_users`
- Include the ticket/issue ID for traceability: `0042_PROJ-123_add_user_preferences.sql`
- Never use spaces or uppercase in filenames

---

## Java / Spring Boot

### Flyway (recommended for Spring Boot)

```
src/main/resources/db/migration/
├── V1__initial_schema.sql
├── V2__add_user_preferences.sql
├── V3__add_orders_index.sql
└── R__seed_reference_data.sql      # Repeatable — re-runs whenever content changes
```

```sql
-- V4__add_payment_status.sql
-- Always include a comment with the JIRA ticket and author

ALTER TABLE orders
    ADD COLUMN payment_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded'));

CREATE INDEX idx_orders_payment_status ON orders(payment_status)
    WHERE payment_status != 'paid';
```

```java
// application.properties — production-safe Flyway config
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.baseline-on-migrate=false        # Never true on existing prod DB without care
spring.flyway.out-of-order=false               # Enforce strict ordering
spring.flyway.validate-on-migrate=true         # Checksum validation — default, keep it
```

**Flyway undo (paid Flyway Teams):**
```sql
-- U4__add_payment_status.sql
ALTER TABLE orders DROP COLUMN payment_status;
DROP INDEX IF EXISTS idx_orders_payment_status;
```

### Liquibase (XML changeset approach)

```xml
<!-- db/changelog/db.changelog-004-add-payment-status.xml -->
<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xsi:schemaLocation="...">

    <changeSet id="004" author="eng-team" labels="PROJ-123">
        <addColumn tableName="orders">
            <column name="payment_status" type="VARCHAR(20)" defaultValue="pending">
                <constraints nullable="false"/>
            </column>
        </addColumn>
        <addCheckConstraint tableName="orders" constraintName="chk_payment_status"
            checkCondition="payment_status IN ('pending', 'paid', 'failed', 'refunded')"/>
        <rollback>
            <dropColumn tableName="orders" columnName="payment_status"/>
        </rollback>
    </changeSet>
</databaseChangeLog>
```

```xml
<!-- db/changelog/db.changelog-master.xml — include each changeset in order -->
<databaseChangeLog>
    <include file="db/changelog/db.changelog-001-initial.xml"/>
    <include file="db/changelog/db.changelog-004-add-payment-status.xml"/>
</databaseChangeLog>
```

---

## Python / SQLAlchemy + Alembic

### Setup
```python
# alembic/env.py — import your Base to enable autogenerate
from app.models import Base  # your SQLAlchemy declarative Base
target_metadata = Base.metadata
```

### Creating migrations
```bash
# Auto-generate from model changes (review ALWAYS before committing)
alembic revision --autogenerate -m "add_user_preferences"

# Create empty migration for complex changes (data migrations, stored procs)
alembic revision -m "backfill_order_totals"
```

```python
# alembic/versions/20240315_142000_add_user_preferences.py

revision = '3a5f8c2e1b0d'
down_revision = '2b4e7a9d0c1f'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_preferences',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('key', sa.String(100), nullable=False),
        sa.Column('value', sa.Text()),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.UniqueConstraint('user_id', 'key', name='uq_user_preferences_user_key')
    )
    op.create_index('ix_user_preferences_user_id', 'user_preferences', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_user_preferences_user_id')
    op.drop_table('user_preferences')
```

**Autogenerate pitfalls — always review the generated diff:**
- Does NOT detect: renamed columns, column type changes requiring data conversion, stored procedures, triggers, custom CHECK constraints (dialect-specific)
- DOES detect: new tables, new columns, dropped columns, index additions/drops, FK additions

### Django Migrations

```bash
# Generate migration from model change
python manage.py makemigrations orders --name=add_payment_status

# Apply pending migrations
python manage.py migrate

# Show migration state
python manage.py showmigrations

# Squash old migrations to reduce startup time
python manage.py squashmigrations orders 0001 0020 --squashed-name=0001_squashed_initial
```

```python
# orders/migrations/0042_add_payment_status.py
class Migration(migrations.Migration):
    dependencies = [('orders', '0041_add_shipping_address')]

    operations = [
        migrations.AddField(
            model_name='order',
            name='payment_status',
            field=models.CharField(
                max_length=20,
                default='pending',
                choices=[('pending','Pending'),('paid','Paid'),('failed','Failed')]
            ),
        ),
    ]
```

---

## TypeScript / Node.js

### Prisma Migrate

```bash
# Development: creates migration file and applies it
prisma migrate dev --name add_user_preferences

# Production: apply pending migrations without creating new ones
prisma migrate deploy

# Preview what will change without applying
prisma migrate diff --from-schema-datamodel ./prisma/schema.prisma --to-schema-datasource
```

```prisma
// prisma/schema.prisma — define schema, let Prisma generate SQL
model UserPreference {
  id        String   @id @default(uuid())
  userId    String
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  key       String   @db.VarChar(100)
  value     String?
  createdAt DateTime @default(now())

  @@unique([userId, key])
  @@index([userId])
}
```

Prisma migrations live in `prisma/migrations/` — one subfolder per migration, each containing a `migration.sql` file. **Never edit these files manually.**

### Drizzle

```typescript
// drizzle.config.ts
export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
});
```

```bash
# Generate migration from schema diff
bunx drizzle-kit generate

# Apply pending migrations
bunx drizzle-kit migrate

# Push schema directly to DB (dev only — no migration file created)
bunx drizzle-kit push

# Preview SQL before applying
bunx drizzle-kit generate --verbose
```

```typescript
// src/db/schema.ts — schema as TypeScript
export const userPreferences = pgTable('user_preferences', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  key: varchar('key', { length: 100 }).notNull(),
  value: text('value'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => ({
  userKeyUnique: unique().on(table.userId, table.key),
  userIdIdx: index('ix_user_preferences_user_id').on(table.userId),
}));
```

---

## Go

### Goose (recommended — SQL and Go migration support)

```bash
# Install
go install github.com/pressly/goose/v3/cmd/goose@latest

# Create a new migration
goose -dir ./db/migrations create add_user_preferences sql

# Apply all pending migrations
goose -dir ./db/migrations postgres "$DATABASE_URL" up

# Rollback one migration
goose -dir ./db/migrations postgres "$DATABASE_URL" down

# Show migration status
goose -dir ./db/migrations postgres "$DATABASE_URL" status

# Apply up to a specific version
goose -dir ./db/migrations postgres "$DATABASE_URL" up-to 20240315142000
```

```sql
-- db/migrations/20240315142000_add_user_preferences.sql
-- +goose Up
CREATE TABLE user_preferences (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key         VARCHAR(100) NOT NULL,
    value       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, key)
);
CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);

-- +goose Down
DROP INDEX IF EXISTS idx_user_preferences_user_id;
DROP TABLE IF EXISTS user_preferences;
```

```go
// Embedding and running goose programmatically
//go:embed db/migrations/*.sql
var migrationFiles embed.FS

func RunMigrations(db *sql.DB) error {
    goose.SetBaseFS(migrationFiles)
    return goose.Up(db, "db/migrations")
}
```

### golang-migrate (alternative — battle-tested, broader driver support)

```bash
# Install
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Create
migrate create -ext sql -dir db/migrations -seq add_user_preferences

# Apply
migrate -path db/migrations -database "$DATABASE_URL" up

# Rollback
migrate -path db/migrations -database "$DATABASE_URL" down 1
```

Files: `000042_add_user_preferences.up.sql` and `000042_add_user_preferences.down.sql`.

### Atlas (schema-first, declarative)

```hcl
# schema.hcl — describe desired state; Atlas diffs against actual DB
table "user_preferences" {
  schema = schema.public
  column "id" { type = uuid; default = sql("gen_random_uuid()") }
  column "user_id" { type = uuid; null = false }
  column "key" { type = varchar(100); null = false }
  column "value" { type = text; null = true }
  primary_key { columns = [column.id] }
  foreign_key "fk_user" { columns = [column.user_id]; references { table = table.users; columns = [column.id] } }
  unique "uq_user_key" { columns = [column.user_id, column.key] }
}
```

```bash
atlas schema apply --url "$DATABASE_URL" --to file://schema.hcl
atlas schema diff --from "$DATABASE_URL" --to file://schema.hcl
```

---

## .NET / EF Core

```bash
# Create migration
dotnet ef migrations add AddUserPreferences --project src/Infrastructure --startup-project src/Api

# Apply pending migrations
dotnet ef database update --project src/Infrastructure --startup-project src/Api

# Generate SQL script (for DBA review)
dotnet ef migrations script --idempotent -o migration.sql

# Remove last migration (only if not yet applied to shared environments)
dotnet ef migrations remove
```

```csharp
// Infrastructure/Migrations/20240315142000_AddUserPreferences.cs
public partial class AddUserPreferences : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "UserPreferences",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                Key = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                Value = table.Column<string>(type: "text", nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_UserPreferences", x => x.Id);
                table.ForeignKey("FK_UserPreferences_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });
        migrationBuilder.CreateIndex("IX_UserPreferences_UserId", "UserPreferences", "UserId");
        migrationBuilder.AddUniqueConstraint("AK_UserPreferences_UserId_Key", "UserPreferences", new[] { "UserId", "Key" });
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "UserPreferences");
    }
}
```

**Bundle deployment (preferred for production — no EF tooling needed at deploy time):**
```bash
dotnet ef migrations bundle --project src/Infrastructure --startup-project src/Api -o efbundle
./efbundle --connection "$DATABASE_URL"
```

---

## Android / Room

```kotlin
@Database(
    entities = [UserEntity::class, PreferenceEntity::class],
    version = 5,        // increment on every schema change
    exportSchema = true  // always true — generates JSON schema for auditing
)
abstract class AppDatabase : RoomDatabase() {
    // ...
    companion object {
        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS user_preferences (
                        id TEXT NOT NULL PRIMARY KEY,
                        user_id TEXT NOT NULL,
                        key TEXT NOT NULL,
                        value TEXT,
                        created_at INTEGER NOT NULL,
                        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
                        UNIQUE(user_id, key)
                    )
                """.trimIndent())
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_user_pref_user_id ON user_preferences(user_id)")
            }
        }
    }
}
```

```kotlin
// Building with migrations — NEVER fallbackToDestructiveMigration in production
Room.databaseBuilder(context, AppDatabase::class.java, "app.db")
    .addMigrations(MIGRATION_4_5)
    // .fallbackToDestructiveMigration()  ← NEVER in production
    .build()
```

**Testing Room migrations:**
```kotlin
@RunWith(AndroidJUnit4::class)
class MigrationTest {
    @get:Rule val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java
    )

    @Test fun migrate4To5() {
        val db = helper.createDatabase(TEST_DB, 4)
        db.execSQL("INSERT INTO users VALUES ('user-1', 'Alice', 'alice@example.com', 0)")
        db.close()

        val migratedDb = helper.runMigrationsAndValidate(TEST_DB, 5, true, MIGRATION_4_5)
        val cursor = migratedDb.query("SELECT * FROM user_preferences")
        assertEquals(0, cursor.count)  // empty table — migration was additive
    }
}
```

---

## Flutter / drift (SQLite ORM)

```dart
// Declare migration in the database class
@DriftDatabase(tables: [Users, UserPreferences])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedReferenceData();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(users, users.profileImageUrl);
      }
      if (from < 3) {
        await m.createTable(userPreferences);
      }
    },
    beforeOpen: (details) async {
      // Enable foreign key enforcement (SQLite-specific)
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
```

**Generate schema snapshot for testing:**
```bash
dart run drift_dev schema dump lib/database/app_database.dart drift_schema
dart run drift_dev schema generate drift_schema/v2.json drift_schema/v3.json lib/database/migrations/
```

---

## KMP / SQLDelight

```sql
-- commonMain/sqldelight/com/example/app/AppDatabase.sqm  ← migration file
-- File name: {version}.sqm, starting from 1.sqm

-- 1.sqm — initial schema applied when no database exists
-- (defined in .sq files, not here)

-- 2.sqm — add user_preferences table
CREATE TABLE user_preferences (
    id TEXT NOT NULL PRIMARY KEY,
    user_id TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(user_id) REFERENCES User(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_user_pref_unique ON user_preferences(user_id, key);
CREATE INDEX idx_user_pref_user_id ON user_preferences(user_id);
```

```kotlin
// commonMain — verify migrations compile
// In your build.gradle.kts, enable verification:
sqldelight {
    databases {
        create("AppDatabase") {
            packageName = "com.example.app"
            verifyMigrations = true  // Fails CI if .sqm files are inconsistent
        }
    }
}
```

---

## DML Migrations (Data Migrations)

DML migrations change data, not schema. They require extra care.

### Patterns

**Backfill new column:**
```sql
-- Always batch for large tables to avoid long-running transactions
-- V42__backfill_order_total.sql
UPDATE orders
SET total_cents = (
    SELECT SUM(line_items.quantity * line_items.unit_price_cents)
    FROM line_items
    WHERE line_items.order_id = orders.id
)
WHERE total_cents IS NULL
  AND created_at < '2024-01-01';
-- Run multiple times until no rows are updated (idempotent!)
```

**Idempotent DML — always write idempotent data migrations:**
```sql
-- Safe to run multiple times
INSERT INTO subscription_plans (id, name, price_cents) VALUES
    ('plan_basic',   'Basic',       999),
    ('plan_pro',     'Pro',        2999),
    ('plan_enterprise', 'Enterprise', 9999)
ON CONFLICT (id) DO NOTHING;
```

**Soft-delete migration (data transform):**
```sql
-- Add deleted_at column (additive — Phase 1)
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;

-- Backfill data (DML migration — separate deployment)
UPDATE users SET deleted_at = now() WHERE is_deleted = true AND deleted_at IS NULL;

-- Drop old column (destructive — Phase 3, after code no longer uses is_deleted)
ALTER TABLE users DROP COLUMN is_deleted;
```

---

## Seed Data Management

Separate seed data by environment and intent:

```
db/
├── migrations/          # Schema changes — version-controlled, immutable
├── seeds/
│   ├── reference/       # Lookup tables, enums, config — safe in all environments
│   │   └── subscription_plans.sql
│   ├── development/     # Realistic fake data for local dev
│   │   └── sample_orders.sql
│   └── test/            # Minimal deterministic data for automated tests
│       └── test_users.sql
```

```sql
-- db/seeds/reference/subscription_plans.sql
-- Idempotent — safe to re-run
INSERT INTO subscription_plans (id, name, price_cents, features) VALUES
    ('plan_free',    'Free',    0,     '{"max_items": 10}'),
    ('plan_starter', 'Starter', 999,   '{"max_items": 100}'),
    ('plan_pro',     'Pro',     2999,  '{"max_items": null}')
ON CONFLICT (id) DO UPDATE SET
    name        = EXCLUDED.name,
    price_cents = EXCLUDED.price_cents,
    features    = EXCLUDED.features;
```

---

## Schema Drift Detection

Schema drift occurs when the actual database schema diverges from what migrations produce.

### PostgreSQL — detect drift with Atlas
```bash
# Compare running DB against your migration-produced schema
atlas schema diff \
  --from "postgres://user:pass@prod-host/dbname" \
  --to "postgres://user:pass@local/dbname"
```

### PostgreSQL — manual drift query
```sql
-- Find tables in DB not in migrations
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name NOT IN (
    'flyway_schema_history', 'schema_migrations', -- migration tracking tables
    'users', 'orders', 'user_preferences'          -- your expected tables
  );
```

### CI drift detection (recommended)
```yaml
# .github/workflows/ci.yml
- name: Detect schema drift
  run: |
    # Apply migrations to a fresh DB
    flyway -url=$TEST_DATABASE_URL migrate
    # Compare against production schema dump
    pg_dump --schema-only $PROD_DATABASE_URL > prod_schema.sql
    pg_dump --schema-only $TEST_DATABASE_URL > test_schema.sql
    diff prod_schema.sql test_schema.sql
```

---

## CI/CD Integration

```yaml
# GitHub Actions — database migration job
jobs:
  migrate:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_DB: testdb, POSTGRES_PASSWORD: secret }
        options: --health-cmd pg_isready

    steps:
      - uses: actions/checkout@v4

      # Flyway example
      - name: Run Flyway migrations
        run: |
          flyway \
            -url=jdbc:postgresql://localhost/testdb \
            -user=postgres \
            -password=secret \
            -locations=classpath:db/migration \
            migrate

      # Validate no pending migrations in CI
      - name: Assert clean state
        run: flyway -url=... info | grep -E "^|Pending" && exit 1 || true
```

**Golden rule for CI migration gates:**
1. Apply all migrations on a fresh DB — catches syntax errors and ordering bugs
2. Run application tests against the migrated DB — catches ORM/query assumptions
3. Assert no pending migrations remain — catches forgotten files
4. Run drift detection — catches manual DB changes that bypass migrations

---

## NoSQL Schema Evolution

### MongoDB
```javascript
// MongoDB has no DDL — schema evolution is application-driven
// Use a migration runner like 'migrate-mongo' or 'umzug'

// migrate-mongo: db/migrations/20240315142000_add_user_prefs_index.js
module.exports = {
  async up(db) {
    await db.collection('users').createIndex(
      { 'preferences.key': 1 },
      { name: 'idx_users_prefs_key', sparse: true }
    );
  },
  async down(db) {
    await db.collection('users').dropIndex('idx_users_prefs_key');
  },
};
```

### DynamoDB attribute evolution
- Add new attributes: no migration needed (schema-less)
- Remove attributes: deploy code that stops writing/reading the attribute, then run a scan+update to remove it
- Rename attributes: copy to new attribute → backfill → update all reads/writes → delete old

### Redis key versioning
```
# Version keys to enable coexistence of old and new schemas
user:v1:{id}:session   → old format
user:v2:{id}:session   → new format
```
Deploy new code that writes both versions, migrate readers, then remove old keys.

---

## Security

- **Never store credentials in migration files** — use environment variables or secret managers
- **Never run migrations as DB superuser** — create a dedicated migration user with DDL privileges only
- **Audit who ran what** — most migration tools log runner identity; enable this in production
- **Validate migration checksums** — Flyway, Liquibase, and Alembic all verify file content hasn't changed; never disable this
- **Review DML migrations for data exfiltration** — `INSERT INTO audit_log SELECT * FROM users` in a migration is a red flag
