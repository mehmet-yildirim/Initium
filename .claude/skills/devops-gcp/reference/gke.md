# GKE Autopilot recipes

Cluster-level GCP resources only. Manifests, Helm charts, policies and autoscaling inside the
cluster follow `devops-kubernetes`.

## Autopilot cluster

```hcl
resource "google_container_cluster" "main" {
  name                = "platform-${var.environment}"
  location            = var.region
  enable_autopilot    = true
  deletion_protection = true

  network    = var.network_id
  subnetwork = var.gke_subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }
}
```

- Autopilot enables Workload Identity Federation, Shielded Nodes and secure boot; node pools
  and machine types are managed for you (use ComputeClasses for Spot, GPU or specific series).
- Reach the control plane through the DNS-based endpoint with IAM, or restrict the IP endpoint
  with master authorized networks — never an unrestricted public endpoint.
- Use maintenance exclusions around peak business periods instead of pinning versions.

## Workload identity with direct principals

Grant roles straight to the Kubernetes ServiceAccount identity. No Google service account, no
annotation, no `roles/iam.workloadIdentityUser` binding.

```hcl
data "google_project" "this" {}

locals {
  wif_pool = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog"
}

resource "google_storage_bucket_iam_member" "reports_reader" {
  bucket = google_storage_bucket.reports.name
  role   = "roles/storage.objectViewer"
  member = "principal://iam.googleapis.com/${local.wif_pool}/subject/ns/reports/sa/reports-api"
}

# Every ServiceAccount in a namespace (use sparingly):
# member = "principalSet://iam.googleapis.com/${local.wif_pool}/namespace/reports"
```

- The Kubernetes side is a plain ServiceAccount `reports-api` in namespace `reports`, referenced
  by the Deployment's `serviceAccountName`.
- A few APIs still reject federated principals. Only then create a Google service account, grant
  the KSA principal `roles/iam.workloadIdentityUser` on it, and annotate the **ServiceAccount**
  (not the pod) with `iam.gke.io/gcp-service-account: NAME@PROJECT.iam.gserviceaccount.com`.
- Identity sameness: every cluster in the project shares the pool, so the same namespace/KSA name
  in another cluster gets the same access — keep sensitive workloads in separate projects.
