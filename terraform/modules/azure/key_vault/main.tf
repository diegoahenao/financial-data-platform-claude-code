# Retrieve the current caller's identity so we can grant it Key Vault access.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                        = var.name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.sku_name
  soft_delete_retention_days  = 7
  purge_protection_enabled    = var.purge_protection_enabled

  # Use Azure RBAC for data-plane authorization instead of legacy access policies.
  rbac_authorization_enabled = true

  # Disable public network access — all traffic goes through the private endpoint.
  public_network_access_enabled = false

  tags = var.tags
}

# Grant the Terraform service principal (or CLI user) full secrets management.
resource "azurerm_role_assignment" "tf_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ==============================================================================
# Private Endpoint — routes all Key Vault traffic through the VNet
# ==============================================================================

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.name}-pe-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id

  private_service_connection {
    name                           = "${var.name}-psc-kv"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [var.private_dns_zone_kv_id]
  }

  tags = var.tags
}
