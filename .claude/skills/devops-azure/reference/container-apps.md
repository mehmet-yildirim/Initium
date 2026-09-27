# Container Apps and ACR recipes (azurerm 5.x)

## Provider

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.ContainerRegistry",
    "Microsoft.KeyVault",
    "Microsoft.OperationalInsights",
  ]
}
```

In CI, authenticate with OIDC via environment variables (`ARM_USE_OIDC=true`, `ARM_CLIENT_ID`,
`ARM_TENANT_ID`) — no client secrets.

## Registry and runtime identity

```hcl
resource "azurerm_user_assigned_identity" "api" {
  name                = "id-api-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_container_registry" "main" {
  name                          = "acr${var.workload}${var.environment}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.app.name
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = var.acr_public_access
  retention_policy_in_days      = 7
}

resource "azurerm_role_assignment" "api_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}

resource "azurerm_role_assignment" "api_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}
```

- Pushing from GitHub-hosted runners needs the public endpoint (`acr_public_access = true`);
  every push and pull still requires Entra auth and the admin user stays disabled.
- Regulated workloads: disable public access, add a private endpoint, and push from VNet-attached
  runners (GitHub Actions Azure private networking or ARC in the spoke).
- `retention_policy_in_days` purges untagged manifests (Premium only).

## Environment (workload profiles, VNet, internal)

```hcl
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.workload}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "main" {
  name                           = "cae-${var.workload}-${var.environment}"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.app.name
  logs_destination               = "log-analytics"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id       = var.aca_subnet_id # /27 or larger, delegated to Microsoft.App/environments
  internal_load_balancer_enabled = true
  public_network_access          = "Disabled"
  zone_redundancy_enabled        = var.environment == "production"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
```

## App with Key Vault secret reference

```hcl
resource "azurerm_container_app" "api" {
  name                         = "ca-api-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.app.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.api.id
  }

  secret {
    name                = "jwt-signing-key"
    identity            = azurerm_user_assigned_identity.api.id
    key_vault_secret_id = azurerm_key_vault_secret.jwt.versionless_id
  }

  ingress {
    external_enabled           = true # external to the environment; the environment itself is internal
    target_port                = 8080
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.environment == "production" ? 1 : 0
    max_replicas = 10

    http_scale_rule {
      name                = "http"
      concurrent_requests = "50"
    }

    container {
      name   = "api"
      image  = var.image # acr.azurecr.io/api@sha256:...
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.api.client_id
      }

      env {
        name        = "JWT_SIGNING_KEY"
        secret_name = "jwt-signing-key"
      }

      startup_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }
    }
  }

  # CI deploys new images by digest.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.api_acr_pull,
    azurerm_role_assignment.api_kv_secrets,
  ]
}
```

- `AZURE_CLIENT_ID` tells `DefaultAzureCredential` which user-assigned identity to use.
- Versionless Key Vault IDs pick up rotated values on the next revision/restart; use a versioned
  ID when rotation must be an explicit deploy.
- Jobs (`azurerm_container_app_job`) use the same identity, registry and secret blocks with a
  `manual_trigger_config`, `schedule_trigger_config`, or `event_trigger_config`.
- Public entry: Front Door Premium with a Private Link origin to the internal environment (see
  `platform.md`).
