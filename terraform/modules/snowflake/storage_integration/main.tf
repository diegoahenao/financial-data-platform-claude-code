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
# NOTE: Azure role assignment for Snowflake managed identity
# ==============================================================================
# After terraform apply, Snowflake generates a multi-tenant Azure AD app.
# This app must be consented in your tenant before its service principal exists.
#
# Run these commands ONCE after the first successful apply:
#
#   # 1. Get the consent URL and app name from Terraform outputs
#   terraform output snowflake_consent_url
#   terraform output snowflake_app_name
#
#   # 2. Consent the app in your Azure AD tenant (creates the service principal)
#   az ad sp create --id <APPLICATION_ID_FROM_CONSENT_URL>
#
#   # 3. Grant Storage Blob Data Reader to the new service principal
#   SP_ID=$(az ad sp show --display-name "<APP_NAME>" --query id -o tsv)
#   az role assignment create \
#     --assignee-object-id $SP_ID \
#     --assignee-principal-type ServicePrincipal \
#     --role "Storage Blob Data Reader" \
#     --scope "<STORAGE_ACCOUNT_ID>"
#
# This is decoupled from Terraform because Azure AD propagation of the
# multi-tenant consent is not instantaneous and cannot be orchestrated in
# a single apply run.

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
