output "managed_identity_id" {
  description = "Resource ID of the Airflow user-assigned managed identity."
  value       = azurerm_user_assigned_identity.airflow.id
}

output "managed_identity_client_id" {
  description = "Client ID of the Airflow managed identity. Use in Airflow connection configs."
  value       = azurerm_user_assigned_identity.airflow.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the Airflow managed identity. Used for role assignments."
  value       = azurerm_user_assigned_identity.airflow.principal_id
}

output "container_app_environment_id" {
  description = "Resource ID of the Airflow Container App Environment."
  value       = azurerm_container_app_environment.airflow.id
}

output "container_app_environment_name" {
  description = "Name of the Airflow Container App Environment."
  value       = azurerm_container_app_environment.airflow.name
}
