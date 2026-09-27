# EF Core 10 (.NET)

Migrations live in the infrastructure project; the API project is only the startup project.

```bash
dotnet ef migrations add AddUserPreferences --project src/Infrastructure --startup-project src/Api
dotnet ef migrations list --project src/Infrastructure --startup-project src/Api
dotnet ef migrations has-pending-model-changes --project src/Infrastructure --startup-project src/Api  # CI gate
dotnet ef migrations script --idempotent -o artifacts/migrate.sql   # DBA review / SQL-based deploys
dotnet ef migrations remove   # only if not applied to any shared environment
```

```csharp
// src/Infrastructure/Migrations/20260915142000_AddUserPreferences.cs
public partial class AddUserPreferences : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("SET LOCAL lock_timeout = '5s';");

        migrationBuilder.CreateTable(
            name: "user_preferences",
            columns: table => new
            {
                id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                user_id = table.Column<Guid>(type: "uuid", nullable: false),
                key = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                value = table.Column<string>(type: "text", nullable: true),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_user_preferences", x => x.id);
                table.ForeignKey("fk_user_preferences_users_user_id", x => x.user_id, "users", "id",
                    onDelete: ReferentialAction.Cascade);
                table.UniqueConstraint("uq_user_preferences_user_id_key", x => new { x.user_id, x.key });
            });
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "user_preferences");
    }
}
```

Concurrent index on an existing table — a separate migration with the transaction suppressed:

```csharp
public partial class AddOrdersCustomerIdIndex : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_orders_customer_id ON orders (customer_id);",
            suppressTransaction: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            "DROP INDEX CONCURRENTLY IF EXISTS ix_orders_customer_id;",
            suppressTransaction: true);
    }
}
```

With Npgsql you can instead declare `.HasIndex(o => o.CustomerId).IsCreatedConcurrently()` in
the model so the generated migration uses `CONCURRENTLY`.

## Deploying

- Prefer a migration bundle built in CI and run as a deploy step; it needs no SDK or source:

  ```bash
  dotnet ef migrations bundle --project src/Infrastructure --startup-project src/Api \
    --self-contained -r linux-x64 -o artifacts/efbundle
  ./artifacts/efbundle --connection "$MIGRATION_DATABASE_URL"
  ```

- Never call `Database.Migrate()` or `EnsureCreated()` from application startup in production.
- `has-pending-model-changes` exits non-zero when the model differs from the latest migration —
  use it in CI to catch forgotten migrations.
