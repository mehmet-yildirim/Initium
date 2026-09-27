# GitHub Actions → Azure with OIDC (federated credentials)

## Deploy identity, federated credential and scoped roles

```hcl
resource "azurerm_user_assigned_identity" "gha_deploy" {
  name                = "id-gha-deploy-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.cicd.name
}

resource "azurerm_federated_identity_credential" "gha" {
  name                      = "github-${var.environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.gha_deploy.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"
}

resource "azurerm_role_assignment" "gha_containerapp" {
  scope                = azurerm_container_app.api.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azurerm_user_assigned_identity.gha_deploy.principal_id
}

# Updating an app that uses a user-assigned identity requires assign/action on that identity.
resource "azurerm_role_assignment" "gha_assign_runtime_identity" {
  scope                = azurerm_user_assigned_identity.api.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.gha_deploy.principal_id
}

resource "azurerm_role_assignment" "gha_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.gha_deploy.principal_id
}
```

- The subject is an exact match: only jobs that declare `environment: production` in this
  repository get a token. Protect the environment with required reviewers and branch rules.
- Pull-request plans use a separate identity with subject `repo:ORG/REPO:pull_request` and only
  `Reader` (plus state storage `Storage Blob Data Reader`).
- If the organization uses GitHub's immutable subject claims, or you need wildcards, use the
  immutable subject format or a flexible federated credential (`claimsMatchingExpression`) —
  never broaden to a whole organization.
- Federated credentials are limited to 20 per identity; use one identity per environment.

## Workflow (build, push by digest, deploy)

```yaml
name: cd-azure
on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: deploy-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: production
    permissions:
      contents: read
      id-token: write
    env:
      ACR_NAME: ${{ vars.ACR_NAME }}
      IMAGE: ${{ vars.ACR_NAME }}.azurecr.io/api
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906 # v3.1.0
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - run: az acr login --name "$ACR_NAME"

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - id: build
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          push: true
          tags: ${{ env.IMAGE }}:${{ github.sha }}
          provenance: mode=max
          sbom: true

      - name: Deploy new revision by digest
        env:
          DIGEST: ${{ steps.build.outputs.digest }}
        run: >
          az containerapp update
          --name "${{ vars.CONTAINER_APP_NAME }}"
          --resource-group "${{ vars.RESOURCE_GROUP }}"
          --image "${IMAGE}@${DIGEST}"
```

- Client, tenant and subscription IDs are identifiers, not secrets; store them as variables.
- For multiple revision mode, deploy with `--revision-suffix`, test the revision FQDN, then
  `az containerapp ingress traffic set` to shift weight.
- `azure/container-apps-deploy-action` only publishes a floating `v2` tag; if you use it, pin the
  commit SHA and review updates manually. The plain CLI above avoids the dependency.
- Terraform applies in CI use the same login pattern with `ARM_USE_OIDC=true` and
  `ARM_CLIENT_ID`/`ARM_TENANT_ID`/`ARM_SUBSCRIPTION_ID` environment variables.
