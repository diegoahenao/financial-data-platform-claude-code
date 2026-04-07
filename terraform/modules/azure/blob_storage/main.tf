locals {
  # Azure storage account names must be lowercase alphanumeric, 3-24 chars.
  storage_account_name = lower(replace(var.storage_account_name, "-", ""))
}

# ==============================================================================
# Storage Account — ADLS Gen2 (Hierarchical Namespace enabled)
# ==============================================================================

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable ADLS Gen2 hierarchical namespace for structured folder paths.
  is_hns_enabled = true

  # Disable public blob access — all access goes through the private endpoint.
  allow_nested_items_to_be_public = false

  # Restrict network access to the VNet only.
  # bypass = AzureServices allows Snowflake's Storage Integration (Managed
  # Identity) to load data via COPY INTO without traversing the private endpoint.
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.subnet_airflow_id, var.subnet_private_endpoints_id]
  }

  tags = var.tags
}

# ==============================================================================
# Containers — one per logical source domain
# ==============================================================================

resource "azurerm_storage_container" "this" {
  for_each = var.landing_containers

  name                  = each.value.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ==============================================================================
# Private Endpoint — routes all blob traffic through the VNet
# ==============================================================================

resource "azurerm_private_endpoint" "blob" {
  name                = "${local.storage_account_name}-pe-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id

  private_service_connection {
    name                           = "${local.storage_account_name}-psc-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [var.private_dns_zone_blob_id]
  }

  tags = var.tags
}
