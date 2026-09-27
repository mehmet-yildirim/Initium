# Deployment Platform Guide

This document helps teams choose a deployment target and provides the setup path for each platform.
Use the `/infra <aws|gcp|azure|onprem> [init|ci|secrets|database|monitoring]` command to scaffold
the actual infrastructure files, and `/deploy <staging|production|canary>` for each deployment
(see [Deployment](04-deployment.md)).

The setup paths below are the short version. Current versions, resource choices, and hardened
examples live in the platform skills — read the one for your target before applying anything:

| Platform | Skill | Also relevant |
|---|---|---|
| AWS | [`devops-aws`](../../../.claude/skills/devops-aws/SKILL.md) | [`devops-terraform`](../../../.claude/skills/devops-terraform/SKILL.md) |
| GCP | [`devops-gcp`](../../../.claude/skills/devops-gcp/SKILL.md) | `devops-terraform` |
| Azure | [`devops-azure`](../../../.claude/skills/devops-azure/SKILL.md) | `devops-terraform` (or Bicep) |
| On-premise | [`devops-onprem`](../../../.claude/skills/devops-onprem/SKILL.md) | [`devops-kubernetes`](../../../.claude/skills/devops-kubernetes/SKILL.md) |
| All | [`devops-cicd`](../../../.claude/skills/devops-cicd/SKILL.md), [`devops-docker`](../../../.claude/skills/devops-docker/SKILL.md), [`devops-observability`](../../../.claude/skills/devops-observability/SKILL.md) | EKS / GKE / AKS manifests follow `devops-kubernetes` |

---

## Platform Selection

```
Do you control the servers?
│
├── NO (cloud provider manages infrastructure)
│       │
│       ├── Need Google ecosystem (BigQuery, Vertex AI, Pub/Sub)?
│       │   └── → Google Cloud Platform (GCP)
│       │
│       ├── Microsoft ecosystem (Entra ID, Microsoft 365, .NET, existing Azure agreement)?
│       │   └── → Microsoft Azure
│       │
│       └── Already invested in AWS, or need broadest service range?
│           └── → Amazon Web Services (AWS)
│
└── YES (you manage the hardware or VMs)
        └── → On-Premise
```

### Quick comparison

| Factor | AWS | GCP | Azure | On-Premise |
|---|---|---|---|---|
| Container workload | ECS Fargate | Cloud Run | Container Apps | k3s / kubeadm (Compose + systemd for a few services) |
| Kubernetes | EKS | GKE Autopilot | AKS (Automatic or Standard) | k3s / kubeadm / RKE2 |
| Managed DB | Aurora PostgreSQL Serverless v2 | Cloud SQL for PostgreSQL | PostgreSQL Flexible Server | CloudNativePG (Kubernetes) or Patroni (VMs) |
| Secrets | Secrets Manager | Secret Manager | Key Vault (RBAC) | OpenBao or Vault + External Secrets Operator |
| Registry | ECR | Artifact Registry | ACR | Harbor |
| CI auth | GitHub OIDC → IAM role | Workload Identity Federation | OIDC federated credential on a user-assigned managed identity | Ephemeral self-hosted runners (ARC scale sets) |
| Ingress / edge | ALB, CloudFront | Load balancer + serverless NEGs | Front Door Standard/Premium | Gateway API (Traefik on k3s, Envoy Gateway on kubeadm) + MetalLB |
| IaC | Terraform or CDK | Terraform | Terraform (azurerm) or Bicep + AVM | Terraform + Ansible |
| Cost model | Pay-per-use | Pay-per-use + scale-to-zero | Pay-per-use + scale-to-zero (Consumption profile) | CapEx (hardware) |
| Compliance | FedRAMP, HIPAA, PCI available | FedRAMP, HIPAA, PCI available | FedRAMP, HIPAA, PCI available | Full control |

Never use ingress-nginx for new work — it was retired in March 2026 and no longer receives
security fixes. Kubernetes routes use Gateway API (`HTTPRoute`); see `devops-kubernetes`.

---

## AWS Setup Path

### Prerequisites
- AWS CLI signed in through IAM Identity Center (SSO) with an administrator permission set for initial setup — no long-lived IAM user keys
- Terraform or OpenTofu installed (supported versions: see `devops-terraform`)
- Docker installed

### Step-by-step

**1. Scaffold infrastructure**
```
/infra aws init
```
This generates: Terraform modules (VPC, ECS, ECR, Aurora), GitHub Actions workflows, and a setup guide.

**2. Bootstrap the AWS account** (one-time)
```bash
bash scripts/bootstrap-aws.sh
# Creates: S3 state bucket (native S3 locking with use_lockfile = true — no DynamoDB lock table), ECR repositories
```

**3. Configure Terraform variables**
Fill in `infrastructure/environments/staging/terraform.tfvars`:
```hcl
aws_account_id = "123456789012"
aws_region     = "eu-west-1"
app_name       = "myapp"
github_org     = "mycompany"
github_repo    = "myapp"
```

**4. Deploy staging infrastructure**
```bash
cd infrastructure/environments/staging
terraform init
terraform plan   # Review before applying
terraform apply
```

**5. Configure GitHub Actions variables** (repository → Settings → Environments → `staging` → Variables)
```
AWS_DEPLOY_ROLE_ARN  = arn:aws:iam::123456789012:role/github-actions-deploy-staging
ECR_REGISTRY         = 123456789012.dkr.ecr.eu-west-1.amazonaws.com
ECR_REPOSITORY       = myapp-staging
ECS_CLUSTER          = myapp-staging
ECS_SERVICE          = myapp-staging
AWS_REGION           = eu-west-1
```
Scope the role's trust policy to the environment claim (`repo:<org>/<repo>:environment:staging`).

**6. Populate secrets** (never in git — read values from a file or prompt, not the command line)
```bash
aws secretsmanager create-secret \
  --name /myapp/staging/api-key \
  --secret-string file://api-key.txt
```
Let Aurora manage its own master credentials (`manage_master_user_password = true`) instead of
creating a database password secret by hand.

**7. Set up database migrations**
```
/db init
```

**8. Trigger first deployment**
```bash
git push origin main   # Triggers cd-staging.yml
```

---

## GCP Setup Path

### Prerequisites
- `gcloud` CLI installed and authenticated
- Terraform or OpenTofu installed (supported versions: see `devops-terraform`)
- Docker installed

### Step-by-step

**1. Scaffold infrastructure**
```
/infra gcp init
```

**2. Bootstrap the GCP project** (one-time)
```bash
bash scripts/bootstrap-gcp.sh
# Enables APIs, creates GCS state bucket, configures Workload Identity Federation
```

**3. Configure Terraform variables**
Fill in `infrastructure/environments/staging/terraform.tfvars`:
```hcl
project_id    = "myapp-staging-123456"
region        = "europe-west1"
app_name      = "myapp"
github_org    = "mycompany"
github_repo   = "myapp"
```

**4. Deploy staging infrastructure**
```bash
cd infrastructure/environments/staging
terraform init -backend-config="bucket=myapp-terraform-state"
terraform plan
terraform apply
```

**5. Configure GitHub Actions variables**
```
GCP_WORKLOAD_IDENTITY_PROVIDER = projects/123456/locations/global/workloadIdentityPools/github-pool/providers/github-provider
GCP_SERVICE_ACCOUNT            = github-deploy-staging@myapp-staging.iam.gserviceaccount.com
GCP_REGION                     = europe-west1
GCP_PROJECT                    = myapp-staging-123456
APP_NAME                       = myapp
CLOUD_RUN_SERVICE              = myapp-staging
```
Restrict the WIF provider's attribute condition to your repository ID (see `devops-gcp`).

**6. Populate secrets** (GCP Console or `gcloud`; keep values out of shell history)
```bash
gcloud secrets versions add myapp-staging-database-url --data-file=database-url.txt
```
Cloud Run should reference a pinned numeric secret version, not `latest`.

**7. Set up database migrations**
```
/db init
```

**8. Trigger first deployment**
```bash
git push origin main   # Triggers cd-staging.yml
```

---

## Azure Setup Path

Details: the [`devops-azure`](../../../.claude/skills/devops-azure/SKILL.md) skill and its
references (`container-apps.md`, `github-oidc.md`, `data.md`, `platform.md`).

### Prerequisites
- Azure CLI (`az`) signed in with an Entra ID account that has PIM-elevated rights on the target subscription
- One subscription per workload per environment, placed in the landing-zone management group hierarchy
- Terraform or OpenTofu installed (`/infra` generates azurerm modules; Bicep + AVM is the alternative for Azure-only teams — do not manage the same resource from both)
- Docker installed

### Step-by-step

**1. Scaffold infrastructure**
```
/infra azure init
```
This generates: Terraform modules (VNet, Container Apps environment and app, ACR, PostgreSQL
Flexible Server), a user-assigned identity with GitHub federated credentials, GitHub Actions
workflows, and a setup guide. Use AKS instead of Container Apps only if you need Kubernetes.

**2. Bootstrap the subscription** (one-time)
```bash
bash scripts/bootstrap-azure.sh
# Creates the Terraform state resource group and storage account; registers resource providers
```

**3. Deploy staging infrastructure**
```bash
cd infrastructure/environments/staging
terraform init
terraform plan
terraform apply
```
The deploy identity's federated credential uses issuer `https://token.actions.githubusercontent.com`,
audience `api://AzureADTokenExchange`, and subject `repo:<org>/<repo>:environment:staging`; its role
assignments are scoped to the resources it deploys — never subscription-wide Contributor.

**4. Configure GitHub Actions variables** (identifiers, not secrets)
```
AZURE_CLIENT_ID       = <deploy identity client ID>
AZURE_TENANT_ID       = <tenant ID>
AZURE_SUBSCRIPTION_ID = <subscription ID>
ACR_NAME              = myappstaging
RESOURCE_GROUP        = rg-myapp-staging
CONTAINER_APP_NAME    = myapp-staging
```

**5. Populate secrets** — prefer managed-identity authentication (databases, Storage, Service Bus)
so there is no secret at all; store the rest in Key Vault and reference them from the app:
```bash
az keyvault secret set --vault-name kv-myapp-staging --name api-key --file api-key.txt
```

**6. Set up database migrations**
```
/db init
```
Run migrations as a Container Apps Job before the new revision rolls out.

**7. Deploy** — the workflow logs in with `azure/login` (pinned by SHA) and deploys by digest:
```bash
az containerapp update --name myapp-staging --resource-group rg-myapp-staging \
  --image myappstaging.azurecr.io/myapp@sha256:<digest>
```

---

## On-Premise Setup Path

### Prerequisites
- 3+ servers (bare metal or VMs) for Kubernetes HA, on a supported LTS distribution
- Network admin access (to configure reserved IPs for MetalLB)
- Ansible (`ansible-core`) installed on your workstation, collections pinned in `requirements.yml`

### Step-by-step

**1. Scaffold infrastructure**
```
/infra onprem init
```

**2. Fill in server IPs**
Edit `ansible/inventories/production/hosts.yml`:
```yaml
k3s_server:
  hosts:
    node1: { ansible_host: 192.168.1.10 }
    node2: { ansible_host: 192.168.1.11 }
    node3: { ansible_host: 192.168.1.12 }
k3s_agent:
  hosts:
    worker1: { ansible_host: 192.168.1.20 }
```

**3. Configure the MetalLB IP pool**
Edit `k8s/metallb-config.yaml` with your reserved IP range (one pool per environment):
```yaml
addresses: ["192.168.1.200-192.168.1.210"]
```

**4. Provision servers with Ansible**
```bash
ansible-playbook -i ansible/inventories/production ansible/site.yml
```

**5. Install Kubernetes and platform services**
```bash
# Install k3s (first server node) — pin an exact version and keep flags in /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<pinned v1.x.y+k3s1>" sh -s - server

# Install MetalLB, cert-manager, External Secrets Operator, and OpenBao;
# enable the Gateway API provider of the bundled Traefik (no ingress-nginx)
bash scripts/install-cluster-tools.sh
```
Chart versions and a hardened k3s config: `devops-onprem` → `reference/k3s-cluster.md`.

**6. Set up Harbor (private registry)**
```bash
helm upgrade --install harbor harbor \
  --repo https://helm.goharbor.io \
  --version <pinned chart version> \
  --namespace registry --create-namespace \
  --values helm/harbor-values.yaml
```

**7. Initialize OpenBao** (MPL-2.0 fork of Vault with a compatible API; use `vault` if you already run Vault)
```bash
bao operator init                    # Split unseal keys and root token; store them offline
bao secrets enable -path=secret kv-v2
bao auth enable kubernetes
```
Configure auto-unseal (HSM, cloud KMS, or transit seal) instead of manual unsealing, and let
External Secrets Operator sync secrets into Kubernetes.

**8. Install ephemeral GitHub Actions runners** (Actions Runner Controller scale sets — never persistent runners)
```bash
helm install arc oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version <pinned> --namespace arc-systems --create-namespace

helm install onprem-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version <pinned> --namespace arc-runners --create-namespace \
  --values runner-values.yaml
```
Runner values (GitHub App auth, runner group, Kubernetes container mode): `devops-onprem` → `reference/delivery.md`.

**9. Deploy to Kubernetes via GitOps**
Register the application with Argo CD or Flux pointing at `k8s/overlays/production` (see
`devops-kubernetes` → `reference/gitops.md`). CI pushes the image to Harbor and commits the new
digest; the controller applies it. Verify:
```bash
kubectl rollout status deployment/myapp -n production
```

---

## CI/CD Workflow Overview (All Platforms)

```
Developer pushes PR
    │
    ├─ ci.yml → lint + typecheck + tests + security scan + build + workflow lint
    │              (same for all platforms — platform-agnostic)
    │
Merge to main
    │
    ├─ cd-staging.yml → build image once → push → attest (SBOM + provenance) → deploy to staging by digest
    │   AWS:     ECR push + register task definition revision + ECS update service
    │   GCP:     Artifact Registry push + Cloud Run deploy (or Cloud Deploy release)
    │   Azure:   ACR push + az containerapp update
    │   On-prem: Harbor push + digest commit → Argo CD / Flux sync
    │
    └─ Smoke tests pass → staging is live
    │
Tag v*.*.* pushed
    │
    ├─ cd-production.yml → promote the same digest → environment approval gate
    │   Production environment requires manual approval in GitHub
    │
    └─ Post-deploy: /deploy monitoring plan
```

Every workflow pins actions by full commit SHA, starts with `permissions: {}` and grants per job,
and authenticates to the cloud with OIDC — complete examples in `devops-cicd` →
`reference/github-actions.md` and each cloud skill's GitHub reference.

---

## Environment Variables Reference

All platforms share the same application-level variable names. Only the values differ.

| Variable | Description | Where stored |
|---|---|---|
| `DATABASE_URL` | Full DB connection string (omit the password where the platform supports IAM / Entra database auth) | AWS: Secrets Manager / GCP: Secret Manager / Azure: Key Vault / On-prem: OpenBao or Vault |
| `JWT_SECRET` | JWT signing secret | Same as above |
| `REDIS_URL` | Redis/Memcached connection | Same as above |
| `NODE_ENV` / `APP_ENV` | Environment name | Plain env var (not sensitive) |
| `PORT` | Container listening port | Plain env var |
| `LOG_LEVEL` | Logging verbosity | AWS: SSM Parameter Store / GCP: Cloud Run env / Azure: Container Apps env / On-prem: ConfigMap |

---

## Runbook: Common Operations

### View live logs
```bash
# AWS
aws logs tail /ecs/myapp/production --follow

# GCP
gcloud run services logs read myapp --project=myapp-prod --region=europe-west1 --limit=50

# Azure
az containerapp logs show --name myapp --resource-group rg-myapp-production --follow

# On-premise
kubectl logs -f -l app.kubernetes.io/name=myapp -n production
```

### Scale the service
```bash
# AWS
aws ecs update-service --cluster myapp-production --service myapp --desired-count 5

# GCP (Cloud Run auto-scales — set max instances)
gcloud run services update myapp --max-instances=20 --region=europe-west1

# Azure (Container Apps auto-scales — set replica bounds)
az containerapp update --name myapp --resource-group rg-myapp-production --min-replicas 2 --max-replicas 20

# On-premise (change replicas or HPA bounds in the GitOps overlay; a manual scale is reverted as drift)
kubectl scale deployment myapp --replicas=5 -n production
```

### Emergency rollback
```bash
# AWS — roll back to previous task definition
aws ecs update-service \
  --cluster myapp-production \
  --service myapp \
  --task-definition myapp:PREVIOUS_REVISION

# GCP — roll back to previous Cloud Run revision
gcloud run services update-traffic myapp \
  --to-revisions=PREV_REVISION=100 \
  --region=europe-west1

# Azure — shift all traffic to the previous revision (multiple revision mode)
az containerapp ingress traffic set --name myapp --resource-group rg-myapp-production \
  --revision-weight PREV_REVISION=100

# On-premise (GitOps) — revert the digest-bump commit; the controller rolls back
git revert <digest-bump-commit> && git push
# Without GitOps
kubectl rollout undo deployment/myapp -n production
```
