# Platform notes: landing zones, policy, Front Door, monitoring, backup, AKS

## Landing zones (ALZ + AVM)

- Bootstrap with the ALZ IaC Accelerator (Terraform or Bicep flavour). It creates the state
  storage, CI identities with federated credentials, and the platform repository.
- Pattern modules: `Azure/avm-ptn-alz/azurerm` (management groups, policy definitions and
  assignments from the ALZ library), `avm-ptn-management-alz` (Log Analytics, automation,
  AMA/DCRs), `avm-ptn-hubnetworking` or `avm-ptn-virtualwan` (connectivity). Pin versions.
- Subscription vending: a module or pipeline that creates a subscription under the right
  management group, peers its spoke to the hub, sets budgets and RBAC groups.
- Migrating from the archived `caf-enterprise-scale` module: follow the ALZ migration guidance,
  importing existing management groups and assignments rather than recreating them.

## Azure Policy as code

```hcl
resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  management_group_id  = var.landing_zones_mg_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  enforce              = var.enforce_policies # start false (DoNotEnforce), flip after compliance review

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })
}
```

- Keep custom definitions and initiatives in the repo; test with `what-if` and
  `az policy state trigger-scan` in a sandbox management group.
- `DeployIfNotExists`/`Modify` assignments need a managed identity with the roles the
  remediation requires; create remediation tasks for existing resources.
- Exemptions are resources in code with an expiry date and a reason.

## Front Door Standard/Premium

- `azurerm_cdn_frontdoor_profile` (`Premium_AzureFrontDoor` when you need Private Link origins,
  managed WAF rule sets or bot protection) → `azurerm_cdn_frontdoor_endpoint` →
  `azurerm_cdn_frontdoor_origin_group` (health probe on `/healthz`) →
  `azurerm_cdn_frontdoor_origin` (with a `private_link` block for internal Container Apps
  environments, App Service or Storage) → `azurerm_cdn_frontdoor_route` (`https_redirect_enabled`,
  `forwarding_protocol = "HttpsOnly"`).
- Custom domains with Front Door managed certificates; TLS 1.2 minimum (the default policy),
  TLS 1.3 negotiated automatically.
- `azurerm_cdn_frontdoor_firewall_policy` in `Prevention` mode with the Microsoft default rule
  set and bot manager rule set (Premium), plus rate-limit custom rules; attach via
  `azurerm_cdn_frontdoor_security_policy`.
- Approve the Private Link connection on the origin side (automate with `azapi` or CLI in the
  pipeline). Lock origins so they accept only Front Door traffic (private link, or the
  `X-Azure-FDID` header check plus the `AzureFrontDoor.Backend` service tag).
- Classic Front Door retires 2027-03-31 and Azure CDN from Microsoft (classic) 2027-09-30 —
  migrate with the portal/CLI migration tooling.

## Monitoring

- One workspace-based Application Insights resource per app and environment, linked to the
  central Log Analytics workspace; disable local (instrumentation-key) authentication and grant
  the app identity `Monitoring Metrics Publisher`.
- Apps use the Azure Monitor OpenTelemetry Distro with `APPLICATIONINSIGHTS_CONNECTION_STRING`
  and Entra credential; keep semantic conventions and sampling per `devops-observability`.
- Diagnostic settings via policy (`DeployIfNotExists`) for every resource type in use.
- Azure Monitor alerts as code: metric alerts for latency/failures, log search alerts for
  business signals, action groups per team; availability (standard) tests for public endpoints.

## Backup and DR

- Azure Backup through a Recovery Services vault (VMs, SQL in VM, Azure Files) or a Backup vault
  (Azure Database for PostgreSQL Flexible long-term retention, blobs, disks, AKS).
- Enable soft delete (always-on) and immutability; lock immutability for production vaults after
  validation. Use cross-region restore or geo-redundant storage where RPO demands it.
- Multi-user authorization (Resource Guard in a separate subscription) for destructive vault
  operations.
- PaaS databases: rely on built-in PITR (7–35 days) plus long-term retention; test restores to a
  new server quarterly.

## AKS

- Prefer AKS Automatic (managed node provisioning, Azure CNI Overlay with Cilium, workload
  identity and image cleaner on by default). Use AKS Standard only when you need node-level
  control; in azurerm 5.x its `node_provisioning_profile` block is required.
- Pick an LTS-eligible version with a planned upgrade channel (`patch` + node OS
  `NodeImage`), maintenance windows, and surge settings for upgrades.
- Private cluster or API server VNet integration with authorized IP ranges; Entra ID
  integration with Azure RBAC for Kubernetes; local accounts disabled.
- Workload identity: OIDC issuer (default on in 5.x) + `workload_identity_enabled = true`; create
  a federated credential on the app's user-assigned identity with subject
  `system:serviceaccount:<namespace>:<serviceaccount>`, annotate the ServiceAccount with
  `azure.workload.identity/client-id`, and label pods `azure.workload.identity/use: "true"`.
- Images from ACR via the kubelet identity (`AcrPull`); Defender for Containers; Azure Policy
  add-on or Kyverno for admission (see `devops-kubernetes`).
