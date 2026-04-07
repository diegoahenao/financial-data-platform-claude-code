output "resource_group_name" {
  description = "Resource group containing the tfstate storage account. Pass to -backend-config."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account name for Terraform remote state. Pass to -backend-config."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container name for Terraform remote state. Pass to -backend-config."
  value       = azurerm_storage_container.tfstate.name
}

output "dbt_artifacts_container_name" {
  description = "Blob container name where dbt production manifests are stored for slim CI."
  value       = azurerm_storage_container.dbt_artifacts.name
}
