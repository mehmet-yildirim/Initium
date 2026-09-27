# PostgreSQL on-premise recipes

## CloudNativePG 1.30 with the Barman Cloud plugin

Install the operator (chart `cnpg/cloudnative-pg`) and the Barman Cloud plugin v0.15.0 in the
operator namespace; the plugin requires cert-manager.

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: backups
  namespace: app
spec:
  retentionPolicy: "30d"
  configuration:
    destinationPath: s3://pg-backups/app/
    endpointURL: https://s3.backup.example.internal
    s3Credentials:
      accessKeyId:
        name: pg-backup-s3          # synced by External Secrets
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: pg-backup-s3
        key: SECRET_ACCESS_KEY
    wal:
      compression: zstd             # zstd/xz are WAL-only
    data:
      compression: lz4
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
  namespace: app
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie
  primaryUpdateStrategy: unsupervised
  enablePDB: true

  bootstrap:
    initdb:
      database: app
      owner: app
      secret:
        name: app-db-owner          # existing basic-auth Secret; omit to let CNPG generate one

  storage:
    size: 100Gi
    storageClass: fast-local
  walStorage:
    size: 20Gi
    storageClass: fast-local

  resources:
    requests:
      cpu: "2"
      memory: 8Gi
    limits:
      memory: 8Gi

  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
    podAntiAffinityType: required

  monitoring:
    enablePodMonitor: true

  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: backups
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: app-db-daily
  namespace: app
spec:
  schedule: "0 0 2 * * *"           # six fields: seconds first
  cluster:
    name: app-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

- Apps connect to the `app-db-rw` Service (reads to `app-db-ro`) with the generated
  `app-db-app` Secret, or through a CNPG `Pooler` (PgBouncer).
- Migrating from in-tree `spec.backup.barmanObjectStore`: create the `ObjectStore` with the same
  destination, move the reference into `spec.plugins`, and switch `ScheduledBackup` to
  `method: plugin` — before upgrading to CNPG 1.31.
- Restore drills: a new `Cluster` with `bootstrap.recovery.source` pointing at an
  `externalClusters` entry that uses the plugin (`barmanObjectName: backups`), optionally with
  `recoveryTarget.targetTime` for PITR.
- Use local NVMe storage classes (TopoLVM, OpenEBS LocalPV) — replication is handled by
  PostgreSQL, not the storage layer.

## VMs: Patroni + pgBackRest

- Three PostgreSQL 18 nodes managed by Patroni with an etcd (3 nodes) DCS; HAProxy health
  checks `/primary` and `/replica` on the Patroni REST API (protected with TLS and basic auth).
- pgBackRest repository on S3-compatible storage with encryption and retention:

```ini
# /etc/pgbackrest/pgbackrest.conf (rendered by Ansible, mode 0640, owner postgres)
[global]
repo1-type=s3
repo1-s3-endpoint=s3.backup.example.internal
repo1-s3-bucket=pg-backups
repo1-s3-region=us-east-1
repo1-path=/app
repo1-s3-key-type=shared
repo1-cipher-type=aes-256-cbc
repo1-retention-full=4
repo1-retention-diff=14
compress-type=zst
process-max=4
start-fast=y

[app]
pg1-path=/var/lib/postgresql/18/main
```

- Supply `repo1-s3-key`, `repo1-s3-key-secret` and `repo1-cipher-pass` through environment
  variables (`PGBACKREST_REPO1_S3_KEY`, …) from OpenBao — not in the file.
- Patroni sets `archive_command: pgbackrest --stanza=app archive-push %p` and uses
  `pgbackrest --stanza=app --delta restore` as the replica create method.
- Schedule weekly full and daily differential backups; run `pgbackrest check` and alert on
  failure. WAL-G is an equivalent alternative (`wal-g backup-push`, `wal-g wal-push`) when the
  team already uses it.
