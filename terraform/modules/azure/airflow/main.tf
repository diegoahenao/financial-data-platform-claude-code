# ==============================================================================
# User Assigned Managed Identity — Airflow runtime identity
# ==============================================================================
# Airflow uses this identity to authenticate to Key Vault (fetch secrets) and
# Blob Storage (read DAG files) without any hardcoded credentials.

resource "azurerm_user_assigned_identity" "airflow" {
  name                = "${var.name_prefix}-id-airflow"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ==============================================================================
# Role Assignments
# ==============================================================================

# Allow Airflow to read secrets (Snowflake credentials, connection strings).
resource "azurerm_role_assignment" "airflow_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.airflow.principal_id
}

# Allow Airflow to read files from the landing zone (if DAGs need direct
# blob access, e.g. file-sensor tasks).
resource "azurerm_role_assignment" "airflow_storage_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.airflow.principal_id
}

# ==============================================================================
# Container App Environment — VNet-injected Airflow runtime
# ==============================================================================
# The Container App Environment is the managed compute plane that hosts
# Airflow's scheduler, webserver, and worker containers inside the VNet.
# Logs are streamed to the Log Analytics Workspace automatically.

resource "azurerm_container_app_environment" "airflow" {
  name                       = "${var.name_prefix}-cae-airflow"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # VNet injection: environment NICs land in the Airflow subnet so all
  # outbound traffic (Snowflake on 443, Azure APIs) is governed by the NSG.
  infrastructure_subnet_id = var.subnet_airflow_id

  tags = var.tags
}
