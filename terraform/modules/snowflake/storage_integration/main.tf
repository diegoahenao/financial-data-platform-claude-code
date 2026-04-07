# ==============================================================================
# Snowflake Storage Integration
# ==============================================================================
# Creates a managed identity in Azure AD that Snowflake uses to authenticate
# to Azure Blob Storage. No shared-access keys are used — only managed identity.
#
# After apply, Snowflake generates an Azure service principal. This module
# automatically grants that principal Storage Blob Data Reader on the storage
# account using the azuread provider.

# Tenant ID is read from the active Azure context at runtime — no hardcoded value needed.
data "azurerm_client_config" "current" {}

resource "snowflake_storage_integration" "this" {
  name    = "${upper(var.environment)}_AZURE_STORAGE_INTEGRATION"
  type    = "EXTERNAL_STAGE"
  enabled = true

  storage_provider = "AZURE"
  azure_tenant_id  = data.azurerm_client_config.current.tenant_id

  # Allow access only to the specific containers in the landing storage account.
  storage_allowed_locations = [
    for container_name in values(var.container_names) :
    "azure://${var.storage_account_name}.blob.core.windows.net/${container_name}/"
  ]

  comment = "Grants Snowflake read access to the ${var.environment} landing zone in Azure Blob Storage."
}

# ==============================================================================
# Azure role assignment — Snowflake managed identity → Blob Storage
# ==============================================================================
# Snowflake creates a multi-tenant service principal in Azure AD after the
# integration is provisioned. We look it up and grant it Storage Blob Data Reader
# so COPY INTO commands can read files from the landing containers.

data "azuread_service_principal" "snowflake" {
  display_name = snowflake_storage_integration.this.azure_multi_tenant_app_name
}

resource "azurerm_role_assignment" "snowflake_storage_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azuread_service_principal.snowflake.object_id

  # Snowflake's service principal may take a few seconds to propagate in Azure AD.
  depends_on = [data.azuread_service_principal.snowflake]
}

# ==============================================================================
# External Stages — one per landing container
# ==============================================================================
# Each stage maps a Snowflake stage object to a Blob Storage container path.
# Airflow DAGs reference these stages in COPY INTO statements.

resource "snowflake_stage" "this" {
  for_each = var.container_names

  name                = "${upper(replace(each.key, "-", "_"))}_STAGE"
  database            = var.database_name
  schema              = "RAW"
  storage_integration = snowflake_storage_integration.this.name
  url                 = "azure://${var.storage_account_name}.blob.core.windows.net/${each.value}/"
  comment             = "External stage for the '${each.key}' landing container. Used by Airflow COPY INTO DAGs."
}

# ==============================================================================
# Grant LOADER role access to all stages
# ==============================================================================

resource "snowflake_grant_privileges_to_account_role" "loader_stage_usage" {
  for_each = snowflake_stage.this

  account_role_name = "LOADER"
  privileges        = ["USAGE", "READ"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "\"${var.database_name}\".\"RAW\".\"${each.value.name}\""
  }
}
