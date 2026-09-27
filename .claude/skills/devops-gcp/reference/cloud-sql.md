# Cloud SQL for PostgreSQL recipes

## Private services access

```hcl
resource "google_compute_global_address" "private_services" {
  name          = "private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = var.network_id
}

resource "google_service_networking_connection" "private_services" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
```

## Instance (edition-aware, private IP, IAM auth)

```hcl
locals {
  is_production = var.environment == "production"
}

resource "google_sql_database_instance" "main" {
  name                = "app-${var.environment}"
  database_version    = "POSTGRES_18"
  region              = var.region
  deletion_protection = local.is_production

  settings {
    # PG16+ defaults to ENTERPRISE_PLUS, which rejects shared-core and db-custom tiers.
    edition           = local.is_production ? "ENTERPRISE_PLUS" : "ENTERPRISE"
    tier              = local.is_production ? "db-perf-optimized-N-4" : "db-custom-1-3840"
    availability_type = local.is_production ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    deletion_protection_enabled = local.is_production

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = local.is_production ? 30 : 7
      }
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "500"
    }

    insights_config {
      query_insights_enabled = true
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "app" {
  name     = "app"
  instance = google_sql_database_instance.main.name
}
```

## IAM database users (no passwords)

```hcl
resource "google_sql_user" "api" {
  instance = google_sql_database_instance.main.name
  name     = trimsuffix(google_service_account.api.email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_project_iam_member" "api_sql" {
  for_each = toset(["roles/cloudsql.client", "roles/cloudsql.instanceUser"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.api.member
}
```

- IAM users start with no table privileges; grant them in a migration
  (`GRANT app_rw TO "api-runtime@PROJECT.iam"`), with the migrator SA owning the schema.
- Connect with the Cloud SQL Language Connector (Go, Java, Python, Node.js) using
  `ipType: PRIVATE` and automatic IAM auth, or the Auth Proxy sidecar with
  `--auto-iam-authn --private-ip`.
- The built-in `postgres` user's password is never set in Terraform; if it must exist, use
  `password_wo` + `password_wo_version` on a `google_sql_user` and store the value in Secret
  Manager for break-glass only.
- Read replicas and cross-region DR replicas inherit edition; Enterprise Plus supports
  near-zero-downtime maintenance and advanced DR switchover.
- Major upgrades: test on a clone (`gcloud sql instances clone`), then upgrade in place with the
  automatic pre-upgrade backup, in a maintenance window.
