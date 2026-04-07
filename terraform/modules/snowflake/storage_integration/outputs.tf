output "integration_name" {
  description = "Name of the Snowflake Storage Integration."
  value       = snowflake_storage_integration.this.name
}

output "azure_consent_url" {
  description = <<-EOT
    URL to grant Snowflake's managed identity consent in your Azure AD tenant.
    Open this URL in a browser and sign in as an Azure AD admin after the first apply.
  EOT
  value = snowflake_storage_integration.this.azure_consent_url
}

output "azure_multi_tenant_app_name" {
  description = "Display name of Snowflake's service principal in Azure AD."
  value       = snowflake_storage_integration.this.azure_multi_tenant_app_name
}

output "stage_names" {
  description = "Map of logical source name to provisioned External Stage name."
  value       = { for k, v in snowflake_stage.this : k => v.name }
}
