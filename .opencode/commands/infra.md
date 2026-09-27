Scaffold deployment infrastructure for the specified platform — Terraform configs, Kubernetes manifests, CI/CD workflows, secrets management, and monitoring setup.

This command generates the infrastructure-as-code and pipeline files an agent or developer needs to deploy an application. Run it once when setting up deployment for a new project or environment.

---

## Subcommands

| Subcommand | What it generates |
|---|---|
| `infra aws init` | Terraform modules (VPC, ECS/EKS, ECR, RDS, CloudFront), OIDC IAM role, GitHub Actions CD workflow |
| `infra gcp init` | Terraform modules (VPC, Cloud Run/GKE, Cloud SQL, Artifact Registry), WIF, GitHub Actions CD workflow |
| `infra onprem init` | Kubernetes manifests, Helm values, Ansible inventory scaffold, Harbor config, GitHub Actions self-hosted runner CD |
| `infra <platform> ci` | Generate or update the CI/CD workflow for the platform only |
| `infra <platform> secrets` | Scaffold secrets management config (Secrets Manager / Secret Manager / Vault) |
| `infra <platform> database` | Scaffold database provisioning Terraform/Ansible for the platform |
| `infra <platform> monitoring` | Scaffold monitoring setup (CloudWatch / Cloud Monitoring / Prometheus+Grafana) |

---

## Step 1: Detect Context

Before generating anything, read:
- `AGENTS.md` or `.project-config.yaml` — app name, language/framework, database choice
- `Dockerfile` (if present) — container port, build stage names
- `agent.config.yaml` — GitHub org/repo, environment names

Identify:
- **Platform**: from `$ARGUMENTS` (`aws` / `gcp` / `onprem`)
- **Subcommand**: from `$ARGUMENTS` (default: `init` if not specified)
- **App name**: from project config (slugified)
- **Container port**: from Dockerfile EXPOSE instruction, or default 3000
- **Database**: PostgreSQL / MySQL / MongoDB / none
- **GitHub repo**: `owner/repo` from project config or ask
- **Environments**: staging + production (default)

State: "Generating [subcommand] for [platform]. App: [name], Port: [N], DB: [type], Repo: [owner/repo]."

---

## `infra aws init` — AWS Infrastructure Scaffold

Generate the following file structure:

```
infrastructure/
├── modules/
│   ├── vpc/
│   │   ├── main.tf        # VPC, public/private subnets, NAT gateway
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecs-service/
│   │   ├── main.tf        # ECS cluster, service, task definition, ALB, security groups
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecr/
│   │   ├── main.tf        # ECR repository, lifecycle policy, scanning
│   │   └── outputs.tf
│   └── rds-postgres/      # Only if database detected
│       ├── main.tf        # Aurora Serverless v2, subnet group, security group
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── staging/
│   │   ├── main.tf        # Calls modules with staging-sized resources
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf        # Calls modules with production-sized resources
│       ├── variables.tf
│       └── terraform.tfvars
├── iam-oidc.tf            # GitHub Actions OIDC provider + deploy role
├── backend.tf             # S3 remote state + DynamoDB lock table
└── providers.tf
```

**`.github/workflows/cd-staging.yml`** — triggered on merge to main:
```yaml
name: Deploy to Staging (AWS)
on:
  push:
    branches: [main]
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      # OIDC auth, ECR login, docker build+push, ECS update, wait for stable
```

**`.github/workflows/cd-production.yml`** — triggered on tag:
```yaml
name: Deploy to Production (AWS)
on:
  push:
    tags: ["v*"]
# ... same steps with production environment and approval gate
```

**`scripts/bootstrap-aws.sh`** — one-time AWS account setup:
```bash
#!/bin/bash
# Creates: S3 state bucket, DynamoDB lock table, ECR repositories
# Run once before `terraform init`
```

**`docs/deployment/aws-setup.md`** — setup guide:
- Prerequisites (AWS CLI, Terraform, required permissions)
- First-time bootstrap steps
- How to add a new environment
- Secret management (how to populate Secrets Manager)
- Runbook for common operations (rollback, scale, logs)

---

## `infra gcp init` — GCP Infrastructure Scaffold

```
infrastructure/
├── modules/
│   ├── vpc/
│   │   ├── main.tf        # VPC, private subnet, Private Service Connect
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cloud-run-service/
│   │   ├── main.tf        # Cloud Run service, VPC connector, IAM invoker
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── artifact-registry/
│   │   ├── main.tf        # Registry, cleanup policy
│   │   └── outputs.tf
│   └── cloud-sql/         # Only if database detected
│       ├── main.tf        # Cloud SQL PostgreSQL, private IP, backups
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── staging/
│   └── production/
├── wif.tf                 # Workload Identity Federation + GitHub deploy SA
├── backend.tf             # GCS remote state
└── providers.tf
```

**`.github/workflows/cd-staging.yml`** and **`cd-production.yml`** — using Workload Identity Federation:
```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
```

**`scripts/bootstrap-gcp.sh`** — enable required APIs, create GCS state bucket, set up WIF:
```bash
gcloud services enable run.googleapis.com sqladmin.googleapis.com ...
gcloud storage buckets create gs://${PROJECT_ID}-terraform-state ...
```

**`docs/deployment/gcp-setup.md`** — setup guide with WIF configuration steps, project IAM, Secret Manager population.

---

## `infra onprem init` — On-Premise Infrastructure Scaffold

```
k8s/
├── namespaces.yaml
├── production/
│   ├── deployment.yaml    # With topology spread, probes, preStop hook
│   ├── service.yaml
│   ├── ingress.yaml       # cert-manager annotation, TLS
│   ├── hpa.yaml           # HorizontalPodAutoscaler
│   ├── configmap.yaml
│   └── networkpolicy.yaml # Default deny + allow specific traffic
├── staging/
│   └── ...                # Same structure, lower replica counts
└── monitoring/
    └── servicemonitor.yaml

ansible/
├── inventories/
│   ├── production/
│   │   ├── hosts.yml      # Server IP addresses (TODOs for user to fill)
│   │   └── group_vars/
│   │       └── all.yml    # Common variables (TODO placeholders)
│   └── staging/
│       └── hosts.yml
├── roles/
│   └── (populated based on detected stack)
├── site.yml               # Main playbook
└── requirements.yml

helm/
└── values-production.yaml
└── values-staging.yaml

.github/workflows/
└── cd-onprem.yml          # Self-hosted runner workflow
```

**`docs/deployment/onprem-setup.md`** — guide for:
- k3s/kubeadm installation commands
- MetalLB IP pool configuration
- Harbor setup and node configuration
- Vault initialization and unseal
- GitHub Actions runner installation

---

## `infra <platform> secrets` — Secrets Management Scaffold

Generate platform-specific secrets infrastructure:

**AWS:**
```hcl
# infrastructure/secrets.tf
# Secrets Manager entries for: DATABASE_URL, JWT_SECRET, API_KEY_*
# ECS task definition secrets array references
# Secret rotation lambda (optional) for database credentials
```

**GCP:**
```hcl
# infrastructure/secrets.tf
# Secret Manager secrets with auto replication
# IAM bindings: Cloud Run SA → secretmanager.secretAccessor
# Cloud Run container secrets array references
```

**On-premise (Vault):**
```hcl
# vault/policies/production.hcl
# vault/roles/myapp-production.tf (Kubernetes auth role)
# k8s/production/deployment-vault-annotations.yaml (with agent inject annotations)
```

Also generate a **`docs/deployment/secrets-management.md`** explaining how to populate secrets in each environment without committing values to git.

---

## `infra <platform> database` — Database Provisioning Scaffold

**AWS (RDS):**
- Aurora Serverless v2 Terraform module
- Security group allowing only app security group
- Secrets Manager for credentials
- Parameter group with performance defaults
- Subnet group in private subnets

**GCP (Cloud SQL):**
- Cloud SQL Terraform resource
- Private IP + Private Service Connect
- Database flags for logging
- Automated backups + PITR for production

**On-premise (PostgreSQL via Ansible):**
- Ansible role: install, configure, primary + replica
- `pg_hba.conf` template with application-only access
- WAL archiving to local NFS
- Streaming replication setup

---

## `infra <platform> monitoring` — Monitoring Scaffold

**AWS (CloudWatch):**
- CloudWatch Dashboard Terraform resource with key metrics
- Alarms: 5xx rate, p99 latency, DB connections, memory
- SNS topic → PagerDuty/Slack integration
- Logs Insights saved queries for common debugging scenarios

**GCP (Cloud Monitoring):**
- Monitoring alert policies Terraform resources
- Notification channel (Slack webhook or PagerDuty)
- Custom dashboard with Cloud Run and Cloud SQL metrics

**On-premise (Prometheus + Grafana):**
- `kube-prometheus-stack` Helm values override file
- `ServiceMonitor` for the application
- AlertManager rules for deployment health
- Grafana dashboard JSON for application metrics

---

## Step 2: Generate Files

Write all scaffolded files. For each TODO placeholder (IPs, project IDs, account IDs):
- Use `YOUR_AWS_ACCOUNT_ID`, `YOUR_GCP_PROJECT_ID`, `YOUR_ORG_NAME` as clear placeholders
- Add inline comments explaining what value is needed

Report each generated file:
```
✅ infrastructure/modules/vpc/main.tf
✅ infrastructure/modules/ecs-service/main.tf
✅ infrastructure/environments/staging/main.tf
✅ infrastructure/environments/production/main.tf
✅ infrastructure/iam-oidc.tf
✅ .github/workflows/cd-staging.yml
✅ .github/workflows/cd-production.yml
✅ scripts/bootstrap-aws.sh
✅ docs/deployment/aws-setup.md
⚠️  terraform.tfvars — contains TODO placeholders for AWS account ID and region
```

---

## Step 3: Next Steps

After generation, provide an ordered setup checklist:

```
╔══════════════════════════════════════════════════════════════╗
║  INFRASTRUCTURE SCAFFOLDED: [platform] / [app name]        ║
╠══════════════════════════════════════════════════════════════╣
║  Next steps:                                                 ║
║  1. Fill in TODO placeholders in terraform.tfvars           ║
║  2. Run: scripts/bootstrap-[platform].sh                    ║
║  3. Run: cd infrastructure/environments/staging && terraform init && terraform apply  ║
║  4. Add GitHub Actions variables (see docs/deployment/*.md) ║
║  5. Run: /db init  to set up database migrations            ║
║  6. Run: /deploy staging  to verify the first deployment    ║
╚══════════════════════════════════════════════════════════════╝
```

---

Platform and subcommand: $ARGUMENTS
(Format: `<platform> [subcommand]` — e.g., `aws init`, `gcp secrets`, `onprem database`, `aws ci`)
