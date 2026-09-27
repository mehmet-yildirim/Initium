# Prisma ORM 7 and Drizzle (TypeScript)

## Prisma 7

Prisma 7 requires `prisma.config.ts` for migrate/db commands; the datasource URL moved out of
`schema.prisma` into it.

```typescript
// prisma.config.ts
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "tsx prisma/seed.ts",
  },
  datasource: {
    url: env("DATABASE_URL"),
    // Only needed by migrate dev / diff --from-migrations; unset in production
    shadowDatabaseUrl: process.env.SHADOW_DATABASE_URL,
  },
});
```

```prisma
// prisma/schema.prisma — no url here in Prisma 7
generator client {
  provider = "prisma-client"
  output   = "../src/generated/prisma"
}

datasource db {
  provider = "postgresql"
}

model UserPreference {
  id        String   @id @default(uuid()) @db.Uuid
  userId    String   @db.Uuid
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  key       String   @db.VarChar(100)
  value     String?
  createdAt DateTime @default(now()) @db.Timestamptz

  @@unique([userId, key])
  @@index([userId])
}
```

```bash
prisma migrate dev --name add_user_preferences   # dev only; no longer runs generate or seed
prisma generate                                  # run explicitly after migrate dev
prisma migrate dev --create-only --name orders_customer_idx   # write SQL, edit, then apply
prisma migrate deploy                            # CI/production: apply pending only
prisma migrate status                            # non-zero exit if pending/failed

# CI: fail if schema.prisma has changes with no migration (needs shadowDatabaseUrl)
prisma migrate diff \
  --from-migrations prisma/migrations \
  --to-schema prisma/schema.prisma \
  --exit-code

# Render SQL between the configured database and the schema, for review
prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script
```

- Prisma 7 removed `--from-url`, `--to-url`, `--from-schema-datasource`,
  `--to-schema-datasource`, `--from-schema-datamodel`, `--to-schema-datamodel` and
  `--shadow-database-url`; use `--from-config-datasource` / `--to-config-datasource`,
  `--from-schema` / `--to-schema`, and `datasource.shadowDatabaseUrl`.
- `--exit-code`: 0 = no difference, 2 = difference, 1 = error.
- Generated `migration.sql` files may be edited **before** they are applied anywhere shared
  (add `lock_timeout`, `NOT VALID`, expand/contract steps). After that they are immutable.
- `CREATE INDEX CONCURRENTLY`: create an empty migration with `--create-only` and make the
  statement the only one in `migration.sql`; multi-statement files run in one implicit
  transaction and fail. Keep the `@@index` in the schema so diffs stay clean.
- Recover a failed production migration with `prisma migrate resolve --rolled-back <name>` (or
  `--applied`) after fixing the database by hand — never delete rows from `_prisma_migrations`.

## Drizzle (drizzle-orm 0.45, drizzle-kit 0.31)

```typescript
// drizzle.config.ts
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema: "./src/infrastructure/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL! },
  strict: true,
  verbose: true,
});
```

Table extras (indexes, constraints) are returned as an **array**; the object form is deprecated:

```typescript
// src/infrastructure/db/schema.ts
import { index, pgTable, text, timestamp, unique, uuid, varchar } from "drizzle-orm/pg-core";

import { users } from "./users";

export const userPreferences = pgTable(
  "user_preferences",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    key: varchar("key", { length: 100 }).notNull(),
    value: text("value"),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    unique("uq_user_preferences_user_key").on(t.userId, t.key),
    index("ix_user_preferences_user_id").on(t.userId),
  ],
);
```

```bash
npx drizzle-kit generate --name add_user_preferences   # writes SQL into ./drizzle
npx drizzle-kit check                                  # validates migration history consistency
npx drizzle-kit migrate                                # applies pending migrations
npx drizzle-kit push                                   # local prototyping only — never shared DBs
```

- Review and edit generated SQL before committing (timeouts, `CONCURRENTLY` in its own
  migration, `NOT VALID`); Drizzle renames are interactive prompts — answer "rename" only when
  it is safe, otherwise implement expand/contract by hand.
- In production, run migrations from a deploy step with `migrate()` from the driver-specific
  `drizzle-orm/<driver>/migrator` module or `drizzle-kit migrate`, not from every app replica.
