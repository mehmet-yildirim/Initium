# Migration CI gates

Pull-request CI only ever talks to throwaway databases it creates itself. It never receives
production credentials or connection strings.

## GitHub Actions example (PostgreSQL + Flyway)

Third-party actions are pinned by full commit SHA; tool images and CLIs are pinned by version.

```yaml
# .github/workflows/migrations.yml
name: migrations

on:
  pull_request:
    paths:
      - "src/main/resources/db/migration/**"
      - "db/schema.sql"

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Lint migrations with squawk
        run: npx --yes squawk-cli@2.66.0 --pg-version=18 src/main/resources/db/migration/*.sql

  apply:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:18.6
        env:
          POSTGRES_DB: app
          POSTGRES_USER: ci
          POSTGRES_PASSWORD: ci-throwaway   # ephemeral container, not a secret
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U ci -d app"
          --health-interval 5s --health-timeout 5s --health-retries 10
    env:
      FLYWAY_IMAGE: flyway/flyway:13.8.0
      PG_IMAGE: postgres:18.6
      FLYWAY_URL: jdbc:postgresql://localhost:5432/app
      FLYWAY_USER: ci
      FLYWAY_PASSWORD: ci-throwaway
      FLYWAY_POSTGRESQL_TRANSACTIONAL_LOCK: "false"
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Apply all migrations to an empty database
        run: |
          docker run --rm --network host \
            -e FLYWAY_URL -e FLYWAY_USER -e FLYWAY_PASSWORD -e FLYWAY_POSTGRESQL_TRANSACTIONAL_LOCK \
            -v "$PWD/src/main/resources/db/migration:/flyway/sql:ro" \
            "$FLYWAY_IMAGE" migrate

      - name: Assert no pending, failed or ignored migrations
        run: |
          docker run --rm --network host \
            -e FLYWAY_URL -e FLYWAY_USER -e FLYWAY_PASSWORD \
            -v "$PWD/src/main/resources/db/migration:/flyway/sql:ro" \
            "$FLYWAY_IMAGE" info -outputType=json > flyway-info.json
          jq -e '[.migrations[] | select(.state | IN("Pending", "Failed", "Ignored"))] | length == 0' \
            flyway-info.json

      - name: Schema snapshot matches migrations
        env:
          PGPASSWORD: ci-throwaway
        run: |
          docker run --rm --network host -e PGPASSWORD "$PG_IMAGE" \
            pg_dump --schema-only --no-owner --no-privileges \
              --exclude-table=flyway_schema_history --restrict-key=schemasnapshot \
              -h localhost -U ci app > schema.generated.sql
          diff -u db/schema.sql schema.generated.sql

      - name: Integration tests against the migrated database
        run: ./gradlew integrationTest
        env:
          SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/app
          SPRING_DATASOURCE_USERNAME: ci
          SPRING_DATASOURCE_PASSWORD: ci-throwaway
          SPRING_FLYWAY_ENABLED: "false"
```

Why each gate exists:

- **squawk** fails the PR on lock-unsafe DDL (non-concurrent index builds, constraints without
  `NOT VALID`, missing `lock_timeout`, column type changes). `pg_dump` and `squawk` run from
  pinned versions matching the production major (18).
- **`jq -e`** exits non-zero when the filter is `false`, so the step actually fails. Never
  use patterns like `grep ... && exit 1 || true`, which always exit 0.
- **Schema snapshot** (`db/schema.sql`, regenerated with the same `pg_dump` command and
  committed with each migration) makes the resulting schema reviewable and catches migrations
  that differ between branches. `--restrict-key` makes the dump repeatable; use it only for
  comparison dumps, never for dumps you restore.

The squawk GitHub Action (`sbdchd/squawk-action`) can post PR comments instead; pin it by SHA
(`sbdchd/squawk-action@f972c01c35289cf7611464dae9a214bb84cce5e4 # v2.2.0`).

## "Models vs. migrations" gate per tool

Run against the CI database; each fails when the ORM model has changes with no migration.

| Tool | Command |
|---|---|
| Prisma 7 | `prisma migrate diff --from-migrations prisma/migrations --to-schema prisma/schema.prisma --exit-code` |
| Alembic | `alembic check` |
| Django | `python manage.py makemigrations --check --dry-run` |
| EF Core | `dotnet ef migrations has-pending-model-changes` |
| Drizzle | `drizzle-kit generate` then fail if it wrote new files; `drizzle-kit check` for history consistency |
| Atlas | `atlas migrate diff --dir file://migrations --to file://schema.hcl --dev-url docker://postgres/18/dev` then fail on new files |
| Rails | `bin/rails db:migrate` then fail if `db/schema.rb` changed; strong_migrations raises on unsafe operations |

## Linters

| Linter | Scope | Notes |
|---|---|---|
| squawk | PostgreSQL SQL files | Free (Apache-2.0/MIT); `--pg-version` tunes rules; `-- squawk-ignore <rule>` for reviewed exceptions |
| Atlas `migrate lint` | Atlas migration directories, many engines | Atlas Pro since v0.38; Community Edition has basic analyzers only |
| strong_migrations | Rails / Active Record | Raises during `db:migrate` with a safe alternative; `safety_assured { }` for reviewed exceptions |

## Production drift detection

Drift (manual hotfixes, console changes) is detected **outside** pull-request CI:

- A scheduled job (e.g. a Kubernetes CronJob) runs inside the production network with a
  read-only role against a read replica, credentials injected from the secrets manager.
- It dumps `pg_dump --schema-only` (or `atlas schema inspect`) and compares it with the schema
  snapshot of the currently deployed migration version, then reports differences to the team's
  alerting channel — no data leaves the network, only the diff summary.
- Resolve drift with a new migration that codifies (or reverts) the manual change.
