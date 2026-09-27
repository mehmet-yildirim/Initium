# Data recipes: PostgreSQL Flexible Server, Azure SQL, Key Vault (azurerm 5.x)

## PostgreSQL Flexible Server 18 (private, Entra-only)

```hcl
locals {
  is_production = var.environment == "production"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.workload}-${var.environment}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.data.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-link"
  resource_group_name   = azurerm_resource_group.data.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.spoke_vnet_id
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-${var.workload}-${var.environment}"
  resource_group_name           = azurerm_resource_group.data.name
  location                      = var.location
  version                       = "18"
  sku_name                      = local.is_production ? "GP_Standard_D4ds_v5" : "B_Standard_B2s"
  storage_mb                    = 131072
  auto_grow_enabled             = true
  zone                          = "1"
  delegated_subnet_id           = var.postgres_subnet_id # delegated to Microsoft.DBforPostgreSQL/flexibleServers
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  backup_retention_days         = local.is_production ? 35 : 7
  geo_redundant_backup_enabled  = local.is_production

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  dynamic "high_availability" {
    for_each = local.is_production ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 3
    start_minute = 0
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "admins" {
  server_name         = azurerm_postgresql_flexible_server.main.name
  resource_group_name = azurerm_resource_group.data.name
  tenant_id           = var.tenant_id
  object_id           = var.db_admin_group_object_id
  principal_name      = var.db_admin_group_name
  principal_type      = "Group"
}

resource "azurerm_postgresql_flexible_server_configuration" "require_tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}
```

- With password auth disabled there is no administrator password in code or state.
- Map the app's managed identity to a database role once (as an Entra admin, connected to the
  `postgres` database): `SELECT * FROM pgaadauth_create_principal('id-api-production', false, false);`
  then `GRANT` the needed privileges in a migration.
- The app requests a token for `https://ossrdbms-aad.database.windows.net/.default` via
  `DefaultAzureCredential` and uses it as the password; refresh before expiry (pool hooks).
- Geo-redundant backup is immutable after creation — decide at create time.

## Azure SQL (Entra-only, serverless outside production)

```hcl
resource "azurerm_mssql_server" "main" {
  name                          = "sql-${var.workload}-${var.environment}"
  resource_group_name           = azurerm_resource_group.data.name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  azuread_administrator {
    login_username              = var.db_admin_group_name
    object_id                   = var.db_admin_group_object_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "app" {
  name           = "app"
  server_id      = azurerm_mssql_server.main.id
  sku_name  = local.is_production ? "BC_Gen5_4" : "GP_S_Gen5_2"

  zone_redundant = local.is_production # the provider only accepts this on Premium/Business Critical

  auto_pause_delay_in_minutes = local.is_production ? null : 60
  min_capacity                = local.is_production ? null : 0.5

  short_term_retention_policy {
    retention_days = local.is_production ? 35 : 7
  }

  long_term_retention_policy {
    weekly_retention  = "P8W"
    monthly_retention = "P12M"
  }
}
```

- Reach the server through a private endpoint (`azurerm_private_endpoint` with subresource
  `sqlServer`) and the central `privatelink.database.windows.net` zone.
- Users: `CREATE USER [id-api-production] FROM EXTERNAL PROVIDER;` plus role membership.
- Enable auditing to Log Analytics (`azurerm_mssql_server_extended_auditing_policy`) and
  Defender for SQL.

## Key Vault (RBAC, purge protection, private)

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                          = "kv-${var.workload}-${var.environment}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.app.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
}

ephemeral "random_password" "jwt" {
  length  = 64
  special = false
}

resource "azurerm_key_vault_secret" "jwt" {
  name             = "jwt-signing-key"
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = ephemeral.random_password.jwt.result
  value_wo_version = 1 # bump to rotate
  content_type     = "text/plain"
}
```

- `value_wo` with an ephemeral value keeps the secret out of plan files and state
  (Terraform ≥ 1.11, `hashicorp/random` ≥ 3.7).
- Writing secrets needs data-plane access: the Terraform identity holds
  `Key Vault Secrets Officer` on this vault and runs from a network that reaches the private
  endpoint. Otherwise, create only the vault in Terraform and let a rotation job add values.
- Grant apps `Key Vault Secrets User` on the vault or individual secrets; alert on
  `SecretGet` failures and access from unexpected identities via diagnostic logs.
