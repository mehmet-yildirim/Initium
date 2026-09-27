---
name: devops-gcp
description: Google Cloud deployment standards — Cloud Run services, jobs, worker pools and GPUs with Direct VPC egress, GKE Autopilot with direct Workload Identity Federation, Cloud SQL for PostgreSQL 18 (edition-aware), Artifact Registry cleanup policies, Secret Manager with pinned versions, GitHub Actions WIF by repository ID, Cloud Build and Cloud Deploy. Targets Terraform google provider 8.x. Use when designing, writing, or reviewing GCP infrastructure, cloudbuild.yaml or clouddeploy.yaml, or GCP deploy pipelines.
globs:
  - "**/gcp/**"
  - "**/cloudbuild.y*ml"
  - "**/clouddeploy.y*ml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# GCP Deployment Standards

GCP-specific architecture and resources. Generic IaC rules (GCS backend, module layout, plan
review, drift) are in `devops-terraform`; Kubernetes manifests for GKE follow `devops-kubernetes`;
pipeline hygiene is in `devops-cicd`; telemetry conventions are in `devops-observability`.

## Baseline and toolchain (September 2026)

- `hashicorp/google ~> 8.0` (8.0 GA 2026-09-22; upgrade from the last 7.x first and clear
  deprecation warnings). Terraform ≥ 1.11 so write-only arguments are available.
- 8.0 behaviour changes to watch: backend services and global forwarding rules default to
  `load_balancing_scheme = "EXTERNAL_MANAGED"`; `secret_data_wo_version` is a string and required
  with `secret_data_wo`.
- Cloud SQL for PostgreSQL 18 (17 acceptable). PostgreSQL 16+ defaults to Enterprise Plus — set
  `edition` explicitly.
- GitHub Actions: `google-github-actions/auth` v3, `setup-gcloud` v3, `deploy-cloudrun` v3 —
  pinned by SHA.

## Resource hierarchy

- Organization → folders (`prod`, `nonprod`, `shared`) → one project per workload per environment.
  Separate projects, not namespaces or labels, isolate environments.
- Organization policies on the root: disable service-account key creation
  (`iam.disableServiceAccountKeyCreation`), enforce uniform bucket-level access and public access
  prevention, restrict resource locations, require OS Login, disable default network creation.
- Shared VPC host project per environment tier; workload projects attach as service projects.
- VPC Service Controls perimeters around projects holding regulated data.
- Humans get access through groups from the IdP; no basic roles (`owner`/`editor`/`viewer`) in
  production.

## Compute choice

| Workload | Use |
|---|---|
| Stateless HTTP/gRPC, WebSockets | Cloud Run service |
| Run-to-completion batch, migrations, scheduled work | Cloud Run job (+ Cloud Scheduler) |
| Continuous pull-based consumers (Pub/Sub pull, Kafka, queues) | Cloud Run worker pool |
| Inference / GPU (NVIDIA L4, RTX PRO 6000) with scale to zero | Cloud Run service or job with GPU |
| Operators, StatefulSets, custom scheduling, multi-team platform | GKE Autopilot |

- Cloud Run is the default. Services scale to zero; set `min_instance_count ≥ 1` only where cold
  starts are measured to matter.
- GPUs on Cloud Run: `node_selector { accelerator = "nvidia-l4" }`, `nvidia.com/gpu = "1"` limit,
  CPU always allocated, at least 4 CPU / 16 GiB; decide zonal redundancy
  (`gpu_zonal_redundancy_disabled`) against quota and availability needs.

Read `reference/cloud-run.md` when writing Cloud Run services, jobs, worker pools or GPU config.

## Networking

- Direct VPC egress (`vpc_access { network_interfaces { … } }`) for Cloud Run — not Serverless
  VPC Access connectors. `egress = "PRIVATE_RANGES_ONLY"` unless all traffic must traverse the VPC.
- Private Google Access on subnets; Cloud NAT for controlled internet egress with static IPs.
- Cloud SQL private IP only (private services access or Private Service Connect); no authorized
  networks.
- Public entry through a global external Application Load Balancer with Cloud Armor, serverless
  NEGs to Cloud Run, and `ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` on the service.

## Data

- Cloud SQL: `edition = "ENTERPRISE"` for shared-core/custom tiers (dev, small prod) or
  `"ENTERPRISE_PLUS"` with `db-perf-optimized-N-*` tiers for 99.99% SLA. Omitting `edition` on
  PG16+ with a shared-core tier fails at create time.
- `availability_type = "REGIONAL"`, PITR, 30-day backup retention and `deletion_protection` in
  production.
- Applications authenticate with IAM database authentication
  (`cloudsql.iam_authentication = on`, `CLOUD_IAM_SERVICE_ACCOUNT` users) through the Cloud SQL
  Language Connectors or Auth Proxy — no database passwords in Secret Manager or state.
- `ssl_mode = "ENCRYPTED_ONLY"` (or `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` without connectors).

Read `reference/cloud-sql.md` when writing Cloud SQL, private service access, or database IAM.

## Secrets

- Secret Manager holds credentials; Terraform creates the secret container and IAM, values are
  added by rotation jobs or `gcloud secrets versions add`. If Terraform must set a value, use
  `secret_data_wo` + `secret_data_wo_version` so it never enters state.
- Cloud Run references a pinned numeric version (`version = var.secret_version`), never
  `"latest"` — rotation becomes an explicit, reviewable deploy that creates a new revision.
- Grant `roles/secretmanager.secretAccessor` on the individual secret to the runtime service
  account only.

## CI/CD identity

- GitHub Actions authenticates with Workload Identity Federation. The provider's
  `attribute_condition` checks immutable IDs:
  `assertion.repository_owner_id == '<org-id>' && assertion.repository_id == '<repo-id>'`.
  Name-based conditions are vulnerable to repository re-registration.
- Map `attribute.environment` and bind the production deploy service account to
  `principalSet://…/attribute.environment/production`, so only jobs in the protected GitHub
  environment can deploy.
- Deploy SA roles: `roles/run.developer` on the project, `roles/artifactregistry.writer` on the
  repository, `roles/iam.serviceAccountUser` on the runtime SA only — never project-wide.

Read `reference/github-wif.md` when writing the WIF pool/provider, deploy IAM, or the workflow.

## Cloud Build and Cloud Deploy

- Cloud Build for builds that must run inside GCP (private pools with VPC access, org-owned
  build provenance). Every build sets a user-managed `serviceAccount` and
  `options.logging: CLOUD_LOGGING_ONLY`; builder images are pinned by digest.
- Cloud Deploy for promotion across targets (`dev → staging → prod`) with approvals, canary
  (`strategy.canary` with `automaticTrafficControl` for Cloud Run), verify jobs and rollback.
  Releases reference images by digest; render with a pinned Skaffold version (≥ 2.17 for worker
  pools).
- GitHub Actions may build and hand off to Cloud Deploy (`gcloud deploy releases create`) instead
  of deploying directly.

Read `reference/cloud-build-deploy.md` when writing `cloudbuild.yaml` or `clouddeploy.yaml`.

## GKE

- Autopilot, regional, private nodes, release channel `REGULAR` (or `STABLE` for regulated
  workloads), maintenance windows and exclusions set.
- Workload Identity Federation for GKE with direct principals: grant IAM roles to
  `principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<project>.svc.id.goog/subject/ns/<ns>/sa/<ksa>`.
  No Google service account or `iam.gke.io/gcp-service-account` annotation unless an API does
  not support federated principals (then the annotation goes on the Kubernetes ServiceAccount,
  never the pod template).
- Binary Authorization with attestations from the build pipeline; Artifact Registry as the only
  allowed registry.

Read `reference/gke.md` when writing GKE clusters or workload identity bindings.

## Supply chain

- Artifact Registry per workload (regional), vulnerability scanning on, cleanup policies that
  include a `DELETE` rule (a `KEEP` rule alone deletes nothing) and run first in dry-run.
- Deploy by digest; sign images and generate SLSA provenance (see `devops-cicd`).

Read `reference/cloud-run.md` (Artifact Registry section) when writing repositories or cleanup
policies.

## Security

- One runtime service account per service with only the roles it needs; never the Compute
  default service account.
- No service account keys anywhere (org policy enforced).
- Cloud Armor (OWASP CRS preconfigured rules, rate limiting) on public load balancers.
- Data Access audit logs for Secret Manager, Cloud SQL and BigQuery; export logs to a locked
  log bucket in a security project.
- CMEK for regulated data; Security Command Center on at organization level.

## Observability

- Apps emit OpenTelemetry (see `devops-observability`) and export OTLP to Google Cloud
  Observability (Cloud Trace/Monitoring/Logging) or a Collector; JSON logs to stdout with
  `logging.googleapis.com/trace` for correlation.
- Alert policies on Cloud Run 5xx ratio and latency (`request_count`, `request_latencies`),
  instance count saturation, Cloud SQL CPU/connections/replication lag.
- Log bucket retention set deliberately; exclusion filters for noisy debug logs.

## Cost

- Cloud Run scale to zero and request-based billing for spiky services; instance-based billing
  for steady or background CPU work.
- Committed use discounts after usage stabilizes; budgets with alerts per project.
- Enterprise edition and zonal Cloud SQL outside production; stop dev instances off-hours.
- Labels (`env`, `team`, `cost-center`) on every resource; billing export to BigQuery.

## Testing

- `terraform test` with `mock_provider` for module logic; apply-mode tests in an ephemeral
  project (see `devops-terraform`).
- Deploy new Cloud Run revisions with `--no-traffic --tag=candidate`, smoke-test the tag URL, then
  shift traffic (or let Cloud Deploy canary do it).
- Policy checks (Checkov/Trivy, `gcloud beta terraform vet` or OPA) in CI.

_Versions verified September 2026._
