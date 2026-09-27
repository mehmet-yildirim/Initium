# Cloud Run and Artifact Registry recipes

Terraform google provider `~> 8.0`. The runtime service account, subnet and secrets are assumed
to exist in the same root module.

## Service with Direct VPC egress and pinned secrets

```hcl
resource "google_service_account" "api" {
  account_id   = "api-runtime"
  display_name = "api runtime"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.environment == "production"

  template {
    service_account                  = google_service_account.api.email
    max_instance_request_concurrency = 80
    timeout                          = "30s"

    scaling {
      min_instance_count = var.environment == "production" ? 1 : 0
      max_instance_count = 20
    }

    vpc_access {
      network_interfaces {
        network    = var.network_id
        subnetwork = var.run_subnet_id
        tags       = ["run-api"]
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.image # region-docker.pkg.dev/project/repo/api@sha256:...

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "DB_INSTANCE"
        value = google_sql_database_instance.main.connection_name
      }

      env {
        name = "JWT_SIGNING_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt.secret_id
            version = var.jwt_secret_version # numeric, never "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 2
        failure_threshold = 15
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
      }
    }
  }

  # CI deploys new images by digest; Terraform owns everything else.
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }

  depends_on = [google_secret_manager_secret_iam_member.api_jwt]
}

resource "google_secret_manager_secret" "jwt" {
  secret_id = "jwt-signing-key"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "api_jwt" {
  secret_id = google_secret_manager_secret.jwt.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}
```

- Add the secret value out of band (`gcloud secrets versions add jwt-signing-key --data-file=-`)
  and bump `jwt_secret_version` in the tfvars to roll it out.
- Firewall rules can target the `run-api` network tag to restrict what the service reaches.
- The Direct VPC subnet needs roughly 2× max instances of free IPs; use a dedicated /24 or larger.

## GPU service (inference)

```hcl
  template {
    gpu_zonal_redundancy_disabled = true # false needs zonal-redundancy quota

    node_selector {
      accelerator = "nvidia-l4"
    }

    containers {
      image = var.inference_image
      resources {
        limits = {
          cpu              = "4"
          memory           = "16Gi"
          "nvidia.com/gpu" = "1"
        }
        cpu_idle = false
      }
    }
  }
```

- Bake model weights into the image or mount a Cloud Storage volume; cold start is dominated by
  model load, so measure it before setting `min_instance_count`.

## Job (migrations, batch)

```hcl
resource "google_cloud_run_v2_job" "migrate" {
  name                = "api-migrate"
  location            = var.region
  deletion_protection = var.environment == "production"

  template {
    task_count = 1

    template {
      service_account = google_service_account.migrator.email
      max_retries     = 0
      timeout         = "900s"

      vpc_access {
        network_interfaces {
          network    = var.network_id
          subnetwork = var.run_subnet_id
        }
        egress = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = var.image
        command = ["/app/migrate"]
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
}
```

Run it from CI with `gcloud run jobs deploy api-migrate --image=…@sha256:… --execute-now --wait`
before shifting traffic to the new service revision. Schedule recurring jobs with Cloud Scheduler
(`google_cloud_scheduler_job` calling the `jobs.run` API with an OAuth token of an invoker SA).

## Worker pool (pull-based consumers)

```hcl
resource "google_cloud_run_v2_worker_pool" "consumer" {
  name                = "orders-consumer"
  location            = var.region
  deletion_protection = var.environment == "production"

  scaling {
    scaling_mode          = "MANUAL"
    manual_instance_count = 2
  }

  template {
    service_account = google_service_account.consumer.email

    containers {
      image = var.consumer_image
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}
```

Worker pools have no endpoint and no request-based autoscaling; scale on queue depth with an
external autoscaler or adjust `manual_instance_count`.

## Artifact Registry with cleanup policies

```hcl
resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "app"
  format        = "DOCKER"
  kms_key_name  = var.kms_key_id

  docker_config {
    immutable_tags = true
  }

  cleanup_policy_dry_run = false # run with true first and review the audit logs

  cleanup_policies {
    id     = "delete-older-than-30d"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "2592000s"
    }
  }

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "keep-releases"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["v"]
    }
  }
}
```

`KEEP` wins over `DELETE`; without a `DELETE` rule nothing is ever removed. Durations must be
given in seconds.
