resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}

# Register Azure resource providers required by this platform.
# These are subscription-level operations; registering once is sufficient.
resource "azurerm_resource_provider_registration" "app" {
  name = "Microsoft.App"
}

resource "azurerm_resource_provider_registration" "container_service" {
  name = "Microsoft.ContainerService"
}
