# goose 3.28, golang-migrate 4.20, Atlas 1.3 (Go and language-agnostic)

Pin tool versions (`go install ...@v3.28.0`, `go tool` directives in `go.mod`) — never
`@latest` in CI.

## goose

```bash
go install github.com/pressly/goose/v3/cmd/goose@v3.28.0

goose -dir ./db/migrations create add_user_preferences sql
goose -dir ./db/migrations postgres "$DATABASE_URL" status
goose -dir ./db/migrations postgres "$DATABASE_URL" up
goose -dir ./db/migrations postgres "$DATABASE_URL" up-to 20260915142000
```

```sql
-- db/migrations/20260915142000_add_user_preferences.sql
-- +goose Up
SET LOCAL lock_timeout = '5s';
CREATE TABLE user_preferences (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key        varchar(100) NOT NULL,
    value      text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, key)
);
CREATE INDEX idx_user_preferences_user_id ON user_preferences (user_id);  -- new table: no traffic yet

-- +goose Down
DROP TABLE IF EXISTS user_preferences;
```

```sql
-- db/migrations/20260916090000_orders_customer_idx.sql
-- +goose NO TRANSACTION
-- +goose Up
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_customer_id;
```

Embedded migrations run from a dedicated command (e.g. `cmd/migrate`), not from the API server:

```go
package migrations

import (
	"context"
	"database/sql"
	"embed"
	"fmt"

	"github.com/pressly/goose/v3"
)

//go:embed *.sql
var files embed.FS

// Up applies all pending migrations embedded in this package.
func Up(ctx context.Context, db *sql.DB) error {
	provider, err := goose.NewProvider(goose.DialectPostgres, db, files)
	if err != nil {
		return fmt.Errorf("create goose provider: %w", err)
	}
	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("apply migrations: %w", err)
	}
	return nil
}
```

## golang-migrate

```bash
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@v4.20.1

migrate create -ext sql -dir db/migrations -seq add_user_preferences
migrate -path db/migrations -database "$DATABASE_URL" up
migrate -path db/migrations -database "$DATABASE_URL" version
```

- Files come in pairs: `000042_add_user_preferences.up.sql` / `.down.sql`.
- A file's statements are sent together, so a multi-statement file runs as one implicit
  transaction on PostgreSQL. Put `CREATE INDEX CONCURRENTLY` alone in its own file.
- A failed migration marks the database `dirty`; fix the schema by hand, then
  `migrate force <version>`. Never `force` without understanding what was half-applied.

## Atlas

Versioned workflow (recommended over `schema apply` against shared databases):

```bash
atlas migrate diff add_user_preferences \
  --dir "file://migrations" \
  --to "file://schema.hcl" \
  --dev-url "docker://postgres/18/dev?search_path=public"

atlas migrate lint --dir "file://migrations" --dev-url "docker://postgres/18/dev" --latest 1
atlas migrate apply --dir "file://migrations" --url "$DATABASE_URL"
```

```hcl
# schema.hcl — desired state
table "user_preferences" {
  schema = schema.public
  column "id" {
    type    = uuid
    default = sql("gen_random_uuid()")
  }
  column "user_id" {
    type = uuid
    null = false
  }
  column "key" {
    type = varchar(100)
    null = false
  }
  column "value" {
    type = text
    null = true
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "fk_user_preferences_user" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.id]
    on_delete   = CASCADE
  }
  unique "uq_user_preferences_user_key" {
    columns = [column.user_id, column.key]
  }
}
```

- `atlas migrate lint` is an Atlas Pro feature since v0.38 (`atlas login`); the Apache-2.0
  Community Edition ships only basic analyzers. Use squawk as the free PostgreSQL linter.
- `atlas schema diff --from <url> --to <url>` compares two schemas; point `--from` at a
  read-only replica role, never embed credentials in the command line of a CI log.
