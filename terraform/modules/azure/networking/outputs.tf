output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_airflow_id" {
  description = "Resource ID of the Airflow worker subnet."
  value       = azurerm_subnet.airflow.id
}

output "subnet_private_endpoints_id" {
  description = "Resource ID of the private endpoints subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_blob_id" {
  description = "Resource ID of the Blob Storage private DNS zone."
  value       = azurerm_private_dns_zone.blob.id
}

output "private_dns_zone_blob_name" {
  description = "Name of the Blob Storage private DNS zone."
  value       = azurerm_private_dns_zone.blob.name
}

output "private_dns_zone_kv_id" {
  description = "Resource ID of the Key Vault private DNS zone."
  value       = azurerm_private_dns_zone.key_vault.id
}

output "private_dns_zone_kv_name" {
  description = "Name of the Key Vault private DNS zone."
  value       = azurerm_private_dns_zone.key_vault.name
}
