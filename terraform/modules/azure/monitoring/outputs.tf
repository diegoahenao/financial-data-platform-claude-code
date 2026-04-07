output "workspace_id" {
  description = "Resource ID of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_name" {
  description = "Name of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.name
}

output "primary_shared_key" {
  description = "Primary shared key for the Log Analytics Workspace. Used by agents to ship logs."
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "action_group_id" {
  description = "Resource ID of the platform alert action group."
  value       = azurerm_monitor_action_group.platform_alerts.id
}
