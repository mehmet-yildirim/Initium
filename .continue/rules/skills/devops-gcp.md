---
name: devops-gcp
description: GCP deployment standards — Cloud Run, GKE, Cloud SQL, Artifact Registry, Secret Manager, IAM Workload Identity, Terraform, Cloud Build, Cloud Deploy. Use when deploying to or writing infrastructure for Google Cloud.
globs:
  - "**/terraform/**/*.tf"
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/cloudbuild.yaml"
  - "**/cloud-run*.yaml"
  - "**/cloud-deploy*.yaml"
  - "**/.github/workflows/cd-gcp*.yml"
  - "**/.github/workflows/*gcp*.yml"
  - "**/service.yaml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# GCP Deployment Standards

## Architecture Patterns

### Container Workloads → Cloud Run (default)
```
Cloud Armor (WAF) → Cloud Load Balancing (HTTPS)
                              ↓
                    Cloud Run Service (managed, auto-scaling)
                         ↓              ↓
               Cloud SQL PostgreSQL    Memorystore Redis
               (private VPC)           (private VPC)
```

### Kubernetes Workloads → GKE Autopilot
Use GKE when: need advanced Kubernetes features, multi-team platform, StatefulSets, or custom scheduling.
Use Cloud Run when: stateless HTTP containers, auto-scaling to zero, simplicity preferred.

### Cloud Run vs GKE decision matrix
| Factor | Cloud Run | GKE Autopilot |
|---|---|---|
| Stateless HTTP | ✅ Ideal | Works |
| Background jobs | Via Cloud Tasks/Scheduler | ✅ CronJob |
| WebSockets | ✅ Supported | ✅ Supported |
| GPU workloads | ❌ | ✅ |
| Custom resource limits | Limited | ✅ Full control |
| Cost at low traffic | ✅ Scale to 0 | Higher baseline |

---

## Infrastructure as Code (Terraform)

### Repository structure
```
infrastructure/
├── modules/
│   ├── cloud-run-service/    # Reusable Cloud Run module
│   ├── cloud-sql/            # Cloud SQL PostgreSQL module
│   ├── vpc/                  # VPC with private service connect
│   └── artifact-registry/   # Container registry module
├── environments/
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       └── terraform.tfvars
├── backend.tf               # GCS remote state
└── providers.tf
```

### Remote state (GCS)
```hcl
terraform {
  backend "gcs" {
    bucket  = "myapp-terraform-state"
    prefix  = "environments/production"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}
```

### VPC with Private Service Connect for Cloud SQL
```hcl
resource "google_compute_network" "vpc" {
  name                    = "${var.app_name}-${var.environment}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private" {
  name          = "${var.app_name}-private-${var.environment}"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = "10.0.1.0/24"

  private_ip_google_access = true   # Required for Cloud SQL private IP
}

# Private Service Access for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.app_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}
```

### Cloud Run service
```hcl
resource "google_cloud_run_v2_service" "app" {
  name     = "${var.app_name}-${var.environment}"
  location = var.region

  template {
    service_account = google_service_account.app.email

    scaling {
      min_instance_count = var.environment == "production" ? 1 : 0
      max_instance_count = var.environment == "production" ? 20 : 5
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}/${var.app_name}:${var.image_tag}"

      resources {
        limits = { cpu = var.cpu_limit, memory = var.memory_limit }
        cpu_idle = true    # Throttle CPU when not handling requests (cost saving)
      }

      ports { container_port = var.container_port }

      env {
        name  = "NODE_ENV"
        value = var.environment
      }

      # Secrets via Secret Manager
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get { path = "/health/ready" }
        initial_delay_seconds = 10
        period_seconds        = 5
        failure_threshold     = 10
      }

      liveness_probe {
        http_get { path = "/health/live" }
        period_seconds = 30
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Allow unauthenticated access (public API)
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.is_public_service ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

---

## Artifact Registry (Container Registry)

```hcl
resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = var.app_name
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  # Vulnerability scanning (requires Container Analysis API)
  description = "${var.app_name} container images"
}
```

---

## GitHub Actions — Workload Identity Federation (no stored credentials)

```hcl
# One-time setup — Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"
}

resource "google_service_account" "github_deploy" {
  account_id   = "github-deploy-${var.environment}"
  display_name = "GitHub Actions Deploy (${var.environment})"
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Minimum permissions for deployment
resource "google_project_iam_member" "github_deploy" {
  for_each = toset([
    "roles/run.developer",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_deploy.email}"
}
```

```yaml
# .github/workflows/cd-production.yml
name: Deploy to Production (GCP)

on:
  push:
    tags: ["v*"]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP (Workload Identity — no stored credentials)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker ${{ vars.GCP_REGION }}-docker.pkg.dev

      - name: Build and push image
        run: |
          IMAGE_URI="${{ vars.GCP_REGION }}-docker.pkg.dev/${{ vars.GCP_PROJECT }}/${{ vars.APP_NAME }}/${{ vars.APP_NAME }}:${{ github.sha }}"
          docker build -t "$IMAGE_URI" .
          docker push "$IMAGE_URI"
          echo "IMAGE_URI=$IMAGE_URI" >> $GITHUB_ENV

      - name: Deploy to Cloud Run
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: ${{ vars.CLOUD_RUN_SERVICE }}
          region: ${{ vars.GCP_REGION }}
          image: ${{ env.IMAGE_URI }}
          flags: "--min-instances=1 --max-instances=20"
```

---

## Secrets Management (Secret Manager)

```hcl
resource "google_secret_manager_secret" "db_url" {
  secret_id = "${var.app_name}-${var.environment}-database-url"

  replication {
    auto {}    # Automatic replication across regions
  }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "postgresql://${var.db_user}:${var.db_password}@${google_sql_database_instance.main.private_ip_address}/${var.db_name}"
}

# Grant Cloud Run SA access to the secret
resource "google_secret_manager_secret_iam_member" "app_db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}
```

**Rules:**
- Never inject secrets as plain environment variables — use Secret Manager references in Cloud Run
- Enable Secret Manager audit logs (included in Cloud Audit Logs)
- Rotate secrets by creating a new version and updating the Cloud Run service reference

---

## Database (Cloud SQL — PostgreSQL)

```hcl
resource "google_sql_database_instance" "main" {
  name             = "${var.app_name}-${var.environment}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.environment == "production" ? "db-custom-2-7680" : "db-f1-micro"
    availability_type = var.environment == "production" ? "REGIONAL" : "ZONAL"

    ip_configuration {
      ipv4_enabled    = false      # Private IP only
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = var.environment == "production"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = var.environment == "production" ? 30 : 7
      }
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
  }

  deletion_protection = var.environment == "production"
}
```

---

## Load Balancing + Cloud Armor (WAF)

```hcl
# Cloud Armor security policy (attach to backend service)
resource "google_compute_security_policy" "app" {
  name = "${var.app_name}-${var.environment}-waf"

  # OWASP Top 10 managed rules
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr { expression = "evaluatePreconfiguredExpr('sqli-v33-stable')" }
    }
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr { expression = "evaluatePreconfiguredExpr('xss-v33-stable')" }
    }
  }

  # Default allow
  rule {
    action   = "allow"
    priority = 2147483647
    match { versioned_expr = "SRC_IPS_V1"; config { src_ip_ranges = ["*"] } }
  }
}
```

---

## GKE Autopilot (when Kubernetes is needed)

```hcl
resource "google_container_cluster" "main" {
  name     = "${var.app_name}-${var.environment}"
  location = var.region

  enable_autopilot = true    # Fully managed node pools

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private.id

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}
```

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels: { app: myapp }
  template:
    metadata:
      labels: { app: myapp }
      annotations:
        # Workload Identity — bind K8s SA to GCP SA
        iam.gke.io/gcp-service-account: app-sa@project.iam.gserviceaccount.com
    spec:
      serviceAccountName: app-ksa
      containers:
        - name: app
          image: europe-docker.pkg.dev/project/myapp/myapp:v1.2.3
          ports: [{ containerPort: 3000 }]
          resources:
            requests: { cpu: 250m, memory: 256Mi }
            limits:   { cpu: 1000m, memory: 512Mi }
          livenessProbe:
            httpGet: { path: /health/live, port: 3000 }
          readinessProbe:
            httpGet: { path: /health/ready, port: 3000 }
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-url
```

---

## Monitoring (Cloud Monitoring + Cloud Logging)

```hcl
# Alert policy — 5xx error rate
resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "${var.app_name}-${var.environment}-high-error-rate"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run 5xx error rate"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "60s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.slack.name]
}
```

---

## Security Checklist

- [ ] Workload Identity Federation configured — no service account keys stored in GitHub
- [ ] Cloud Run service account follows least privilege (no `roles/editor` or `roles/owner`)
- [ ] Cloud SQL uses private IP only (`ipv4_enabled = false`)
- [ ] VPC Service Controls configured for production project (prevents data exfiltration)
- [ ] Binary Authorization enabled — only signed images from Artifact Registry can deploy
- [ ] Cloud Armor WAF attached to load balancer in production
- [ ] Organization policies: disable public Cloud Storage bucket creation, require OS Login
- [ ] Cloud Audit Logs enabled for data access (BigQuery, Cloud SQL, Secret Manager)
- [ ] Separate GCP projects per environment (not just separate namespaces)
