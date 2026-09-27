# Flyway 13 and Liquibase 5 (Java / Spring Boot)

## Flyway layout

```
src/main/resources/db/migration/
├── V1__initial_schema.sql
├── V2__add_orders_payment_status.sql
├── V3__orders_payment_status_idx.sql
├── V3__orders_payment_status_idx.sql.conf   # executeInTransaction=false
└── R__reference_data.sql                    # repeatable: re-runs when its checksum changes
```

```sql
-- V2__add_orders_payment_status.sql  (PROJ-123)
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER TABLE orders
    ADD COLUMN payment_status varchar(20) NOT NULL DEFAULT 'pending';
ALTER TABLE orders
    ADD CONSTRAINT chk_orders_payment_status
    CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')) NOT VALID;
```

Non-transactional index build — the statement is alone in its file:

```sql
-- V3__orders_payment_status_idx.sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_payment_status
    ON orders (payment_status)
    WHERE payment_status <> 'paid';
```

```properties
# V3__orders_payment_status_idx.sql.conf  (script configuration — Community tier)
executeInTransaction=false
```

Flyway's default PostgreSQL advisory lock is transactional and makes the concurrent build wait
on Flyway's own transaction. Switch to session-level locks globally:

```toml
# flyway.toml
[flyway]
locations = ["filesystem:src/main/resources/db/migration"]
validateOnMigrate = true
outOfOrder = false
cleanDisabled = true

[flyway.postgresql]
transactional.lock = false
```

## Spring Boot

```yaml
# application.yml — credentials come from the environment, never from this file
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false      # only true for a one-off adoption on an existing DB
    out-of-order: false
    validate-on-migrate: true
    clean-disabled: true
    postgresql:
      transactional-lock: false
```

- In production, run Flyway as a separate deploy step (CLI, Docker image `flyway/flyway`, or a
  one-off job) with the migration role; set `spring.flyway.enabled=false` in the app replicas.
- Undo migrations (`U2__...sql`) are a paid Flyway feature; prefer forward fixes anyway.

## Checking state in scripts

```bash
# Fails (exit 1) if any migration is pending, failed or ignored
flyway info -outputType=json \
  | jq -e '[.migrations[] | select(.state | IN("Pending", "Failed", "Ignored"))] | length == 0'
```

`-outputType=json` puts errors in the JSON payload instead of stderr, so always test with
`jq -e` rather than relying on grep over human-readable tables.

## Liquibase

```xml
<!-- db/changelog/changes/004-add-payment-status.xml -->
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">

    <changeSet id="004-add-payment-status" author="orders-team" labels="PROJ-123">
        <sql>SET LOCAL lock_timeout = '5s'</sql>
        <addColumn tableName="orders">
            <column name="payment_status" type="varchar(20)" defaultValue="pending">
                <constraints nullable="false"/>
            </column>
        </addColumn>
        <rollback>
            <dropColumn tableName="orders" columnName="payment_status"/>
        </rollback>
    </changeSet>

    <changeSet id="005-orders-payment-status-idx" author="orders-team" runInTransaction="false">
        <sql>CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_payment_status
             ON orders (payment_status)</sql>
        <rollback>
            <sql>DROP INDEX CONCURRENTLY IF EXISTS idx_orders_payment_status</sql>
        </rollback>
    </changeSet>
</databaseChangeLog>
```

```xml
<!-- db/changelog/db.changelog-master.xml -->
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">
    <include file="changes/001-initial.xml" relativeToChangelogFile="true"/>
    <include file="changes/004-add-payment-status.xml" relativeToChangelogFile="true"/>
</databaseChangeLog>
```

- Changeset `id` + `author` + file path form the identity; never edit an applied changeset.
- `liquibase update-sql` renders SQL for DBA review; `liquibase status --verbose` lists pending
  changesets.
