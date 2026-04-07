output "storage_account_name" {
  description = "Actual name of the provisioned storage account (hyphens stripped)."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint URL."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Map of logical source name to provisioned container name."
  value       = { for k, v in azurerm_storage_container.this : k => v.name }
}
