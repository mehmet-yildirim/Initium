---
name: devops-azure
description: Azure deployment standards — landing zones with management groups and Azure Policy (AVM/ALZ), Container Apps and AKS with managed and workload identity, Azure Database for PostgreSQL Flexible Server 18 and Azure SQL with Entra-only auth, Key Vault RBAC, GitHub Actions OIDC via federated credentials, Front Door Standard/Premium, Azure Monitor with the OpenTelemetry Distro, and Azure Backup. Covers Terraform azurerm 5.x vs Bicep and azd. Use when designing, writing, or reviewing Azure infrastructure, Bicep files, azure.yaml, or Azure deploy pipelines.
paths:
  - "**/azure/**"
  - "**/*.bicep"
  - "**/*.bicepparam"
  - "**/azure.yaml"
---

# Azure Deployment Standards

Azure-specific architecture and resources. Generic IaC rules (azurerm backend, module layout,
plan review, drift) are in `devops-terraform`; AKS manifests follow `devops-kubernetes`;
pipelines, including `azure-pipelines*.yml`, follow `devops-cicd`; telemetry conventions are in
`devops-observability`.

## Baseline and toolchain (September 2026)

- Terraform: `hashicorp/azurerm ~> 5.0` (5.0 GA 2026-07-27). Set `subscription_id` explicitly and
  list `resource_providers_to_register` — 5.x no longer registers providers by default.
- 5.x breaking changes to know: Key Vault `rbac_authorization_enabled` is required;
  `azurerm_federated_identity_credential` takes `user_assigned_identity_id`; Container Apps
  environments need `logs_destination = "log-analytics"` to attach a workspace; single-server
  PostgreSQL resources are gone; SQL minimum TLS is 1.2 only.
- Bicep 0.47 with Azure Verified Modules (`br/public:avm/...`) and `.bicepparam` files; Azure
  Developer CLI (azd) 1.34 for app-team templates (`azure.yaml`).
- AKS 1.35/1.36 GA (1.37 due October 2026); every AKS version offers LTS.
- PostgreSQL Flexible Server 18 (GA since December 2025); Azure SQL Database.
- GitHub Actions: `azure/login` v3 pinned by SHA with OIDC.

## Terraform or Bicep

| Choose | When |
|---|---|
| Terraform azurerm (+ azapi for day-0 preview APIs) | Multi-cloud estate, existing Terraform platform, shared modules and state tooling |
| Bicep + AVM + deployment stacks | Azure-only teams, same-day API coverage, no state file to protect |
| azd on top of Bicep or Terraform | App templates where developers run `azd up` into sandbox subscriptions |

- Pick one per landing zone layer; don't manage the same resource from both.
- Bicep: `targetScope` explicit, parameters in `.bicepparam`, `@secure()` for secret params,
  `az deployment group what-if` in PR checks, deployment stacks with `--action-on-unmanage` to
  handle deletions, `bicep lint` with `bicepconfig.json` rules as errors.
- Pin module versions (AVM registry tags or Terraform module versions) and let Renovate bump them.

## Landing zones and governance

- Management group hierarchy per Azure Landing Zones: `Platform` (identity, management,
  connectivity), `Landing zones` (`Corp`, `Online`), `Sandbox`, `Decommissioned`. One
  subscription per workload per environment.
- Deploy with the ALZ IaC Accelerator using the AVM pattern modules (`avm-ptn-alz`,
  `avm-ptn-management-alz`, hub networking or Virtual WAN). The CAF enterprise-scale module is
  archived — migrate off it.
- Azure Policy as code: assign the ALZ initiatives (deny public IPs on Corp, require private
  endpoints, allowed regions, diagnostic settings to Log Analytics, Defender for Cloud plans).
  Start new assignments with `enforcementMode = DoNotEnforce`, review compliance, then enforce.
- Humans use Entra ID groups with PIM for privileged roles; no standing Owner assignments.

Read `reference/platform.md` when working on landing zones, policy, Front Door, monitoring,
backups, or AKS.

## Compute choice

| Workload | Use |
|---|---|
| HTTP APIs, workers, event-driven jobs, scale to zero | Azure Container Apps (workload profiles environment) |
| Kubernetes-native platform, operators, fine-grained networking | AKS (Automatic for most teams, Standard when you need node control) |
| Event-driven functions | Azure Functions Flex Consumption |

- Container Apps: workload profiles environment in your VNet (`infrastructure_subnet_id`,
  /27 minimum), internal load balancer behind Front Door or Application Gateway for public apps,
  Container Apps Jobs for batch and migrations.
- Pull images from ACR with a user-assigned managed identity (`AcrPull`); no admin user, no
  registry passwords.

Read `reference/container-apps.md` when writing Container Apps environments, apps, jobs, or ACR.

## Identity and secrets

- Managed identities everywhere: user-assigned identities for apps (stable across redeploys,
  pre-grantable), system-assigned only for single-resource cases.
- Key Vault with RBAC authorization, purge protection, private endpoint and public access
  disabled. Apps get `Key Vault Secrets User` on the vault (or individual secret), never
  `Key Vault Administrator`.
- Container Apps reference secrets with `key_vault_secret_id` + identity; AKS uses Workload
  Identity with the Key Vault CSI driver or External Secrets.
- Prefer Entra authentication over secrets entirely: databases, Storage, Service Bus, Cosmos DB
  and Event Hubs all accept managed identity tokens.

## CI/CD identity

- GitHub Actions authenticates with a user-assigned managed identity plus a federated identity
  credential: issuer `https://token.actions.githubusercontent.com`, audience
  `api://AzureADTokenExchange`, subject `repo:ORG/REPO:environment:production`.
- One identity per environment with role assignments scoped to the resources it deploys:
  `Container Apps Contributor` on the app, `Managed Identity Operator` on the app's runtime
  identity, `AcrPush` on the registry — never subscription-wide Contributor. That role can list
  app secrets, so keep secret values in Key Vault references.
- Terraform plans run with a read-only identity on PRs; applies use a separate identity bound to
  the protected environment.

Read `reference/github-oidc.md` when writing federated credentials, deploy roles, or the workflow.

## Data

- PostgreSQL Flexible Server 18: private access (delegated subnet + private DNS zone) or
  private endpoint, Entra-only authentication (`password_auth_enabled = false`), zone-redundant
  HA and geo-redundant backup in production, 35-day retention.
- Azure SQL: `azuread_authentication_only = true`, TLS 1.2, private endpoint, auditing to Log
  Analytics, long-term retention policies for compliance.
- Applications connect with their managed identity token (`DefaultAzureCredential` /
  `ManagedIdentityCredential`); no connection-string passwords.

Read `reference/data.md` when writing PostgreSQL, Azure SQL, or Key Vault resources.

## Edge and networking

- Front Door Standard/Premium (classic retires 2027-03-31) with managed certificates, WAF policy
  in Prevention mode (Premium: managed rule sets + bot protection), and Private Link origins to
  internal Container Apps or App Service.
- Hub-and-spoke or Virtual WAN from the landing zone; spokes get private endpoints and private
  DNS zones linked centrally; outbound via Azure Firewall or NAT Gateway.
- Disable public network access on PaaS resources unless the resource is the intended edge.

## Security

- Defender for Cloud plans for servers, containers, databases, Key Vault and storage in
  production subscriptions.
- Diagnostic settings for every resource to the central Log Analytics workspace (enforced by
  policy); activity logs retained per compliance needs.
- Resource locks (`CanNotDelete`) on production data stores and the Key Vault.
- No secrets in Bicep outputs, Terraform outputs, or app settings; `@secure()` / `sensitive`.

## Observability

- Instrument apps with the Azure Monitor OpenTelemetry Distro (`azure-monitor-opentelemetry`,
  `@azure/monitor-opentelemetry`, `Azure.Monitor.OpenTelemetry.AspNetCore`, Java agent 3.7) and a
  workspace-based Application Insights resource; authenticate ingestion with Entra ID
  (disable local auth).
- Container Apps: environment logs to Log Analytics; consider the managed OpenTelemetry agent to
  forward to App Insights or another OTLP backend.
- Alerts: availability tests, failure rate, latency percentiles, replica restarts, database CPU,
  storage and connection counts. Action groups route to on-call.

## Cost

- Consumption workload profile and scale-to-zero for non-production Container Apps.
- Burstable PostgreSQL tiers outside production; stop dev servers off-hours.
- Reservations or savings plans after usage stabilizes; budgets and cost alerts per subscription.
- Tags (`env`, `owner`, `costCenter`) enforced by policy.

## Testing

- Terraform: `terraform test` with mocks, apply tests in a sandbox subscription (see
  `devops-terraform`); Bicep: `bicep lint`, `what-if`, and PSRule for Azure in CI.
- Policy compliance scan of the target scope after deploy; fail the pipeline on new
  non-compliant resources.
- Smoke-test new Container Apps revisions via their revision FQDN (multiple revision mode)
  before shifting traffic.

_Versions verified September 2026._
