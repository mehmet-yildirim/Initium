# Alembic 1.20 and Django 6.1 (Python)

## Alembic

```python
# alembic/env.py — expose metadata for autogenerate; URL comes from the environment
import os

from alembic import context

from app.infrastructure.db.models import Base

config = context.config
# configparser interpolates "%", so escape it in URL-encoded passwords
config.set_main_option("sqlalchemy.url", os.environ["DATABASE_URL"].replace("%", "%%"))
target_metadata = Base.metadata
```

```bash
alembic revision --autogenerate -m "add_user_preferences"   # always review the output
alembic revision -m "backfill_order_totals"                  # hand-written
alembic upgrade head
alembic upgrade head --sql > upgrade.sql                     # offline SQL for review
alembic check                                                # fails if models differ from migrations
```

```python
# alembic/versions/20260915_142000_add_user_preferences.py
import sqlalchemy as sa
from alembic import op

revision = "3a5f8c2e1b0d"
down_revision = "2b4e7a9d0c1f"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("SET LOCAL lock_timeout = '5s'")
    op.create_table(
        "user_preferences",
        sa.Column("id", sa.UUID(), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", sa.UUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("key", sa.String(100), nullable=False),
        sa.Column("value", sa.Text()),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "key", name="uq_user_preferences_user_key"),
    )


def downgrade() -> None:
    op.drop_table("user_preferences")
```

Concurrent index on an existing table — leave Alembic's transaction for this block:

```python
def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_orders_customer_id",
            "orders",
            ["customer_id"],
            postgresql_concurrently=True,
            if_not_exists=True,
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        op.drop_index("ix_orders_customer_id", table_name="orders",
                      postgresql_concurrently=True, if_exists=True)
```

Constraints without a scan, validated in a later revision:

```python
op.create_check_constraint(
    "chk_users_email_not_null", "users", "email IS NOT NULL", postgresql_not_valid=True
)
# next revision
op.execute("ALTER TABLE users VALIDATE CONSTRAINT chk_users_email_not_null")
```

Autogenerate does **not** detect renames (it emits drop + add — data loss), server-default
changes by default, or custom CHECK constraints, triggers and functions. Rewrite renames as
expand/contract by hand.

## Django

```bash
python manage.py makemigrations orders --name add_payment_status
python manage.py makemigrations --check --dry-run    # CI: fails if models lack a migration
python manage.py sqlmigrate orders 0042               # review the SQL
python manage.py migrate
```

```python
# orders/migrations/0042_add_payment_status.py
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("orders", "0041_add_shipping_address")]

    operations = [
        migrations.AddField(
            model_name="order",
            name="payment_status",
            field=models.CharField(
                max_length=20,
                default="pending",
                db_default="pending",
                choices=[("pending", "Pending"), ("paid", "Paid"), ("failed", "Failed")],
            ),
        ),
    ]
```

`db_default` puts the default in the database so old code that omits the column keeps working
during a rollout.

```python
# orders/migrations/0043_order_payment_status_idx.py
from django.contrib.postgres.operations import AddIndexConcurrently
from django.db import migrations, models


class Migration(migrations.Migration):
    atomic = False
    dependencies = [("orders", "0042_add_payment_status")]

    operations = [
        AddIndexConcurrently(
            "order",
            models.Index(fields=["payment_status"], name="order_payment_status_idx"),
        ),
    ]
```

- Use `AddConstraintNotValid` + `ValidateConstraint` from `django.contrib.postgres.operations`
  for CHECK constraints on large tables.
- Data migrations use `RunPython` with `apps.get_model(...)` (never import models directly) and
  iterate in batches; mark them `elidable=True` if they may be dropped when squashing.
- Squash long histories with `squashmigrations` only after every environment has applied them.
