# ==============================================================================
# Log Analytics Workspace
# ==============================================================================
# Central sink for all platform logs — Airflow DAGs, Azure resource diagnostics,
# and container metrics. Satisfies the CLAUDE.md observability requirement:
# "Every Airflow DAG must emit structured logs and be observable via Azure Monitor."

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# ==============================================================================
# Azure Monitor Action Group
# ==============================================================================
# Routes alert notifications to the on-call team email.
# Attach this action group to metric alert rules as needed.

resource "azurerm_monitor_action_group" "platform_alerts" {
  name                = "${var.name_prefix}-ag-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "plat-alert"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email
    }
  }
}
