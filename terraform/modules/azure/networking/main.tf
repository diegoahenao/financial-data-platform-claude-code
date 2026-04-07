# ==============================================================================
# Virtual Network
# ==============================================================================

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# ==============================================================================
# Subnets
# ==============================================================================

# Hosts Azure Managed Airflow worker nodes (VNet-injected).
# Add a subnet delegation here if your Airflow managed service requires it.
resource "azurerm_subnet" "airflow" {
  name                 = "snet-airflow"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_airflow_cidr]
}

# Hosts all private endpoint NICs — one NIC per private endpoint.
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_private_endpoints_cidr]
}

# ==============================================================================
# Network Security Groups
# ==============================================================================

resource "azurerm_network_security_group" "airflow" {
  name                = "${var.name_prefix}-nsg-airflow"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow Airflow workers to reach Snowflake, dbt Hub, PyPI, and Azure APIs.
  security_rule {
    name                       = "allow-outbound-https"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  # Allow all traffic within the VNet (private endpoints, internal services).
  security_rule {
    name                       = "allow-outbound-vnet"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Deny everything else outbound.
  security_rule {
    name                       = "deny-outbound-other"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Block all inbound from the public internet.
  security_rule {
    name                       = "deny-inbound-internet"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${var.name_prefix}-nsg-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow inbound from the VNet so Airflow and other internal services can
  # resolve and reach private endpoints.
  security_rule {
    name                       = "allow-inbound-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Block all inbound from the internet.
  security_rule {
    name                       = "deny-inbound-internet"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# ==============================================================================
# NSG → Subnet associations
# ==============================================================================

resource "azurerm_subnet_network_security_group_association" "airflow" {
  subnet_id                 = azurerm_subnet.airflow.id
  network_security_group_id = azurerm_network_security_group.airflow.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ==============================================================================
# Private DNS Zones
# ==============================================================================
# Each zone intercepts DNS queries from within the VNet and returns the private
# IP of the corresponding private endpoint instead of the public IP.

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ==============================================================================
# Private DNS Zone → VNet links
# ==============================================================================
# Without these links, VMs and services inside the VNet cannot resolve
# private endpoint hostnames.

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "${var.name_prefix}-dns-link-blob"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "${var.name_prefix}-dns-link-kv"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
