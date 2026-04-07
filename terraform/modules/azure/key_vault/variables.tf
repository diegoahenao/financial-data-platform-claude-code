variable "name" {
  description = "Name of the Azure Key Vault. Must be globally unique, 3-24 characters."
  type        = string
  validation {
    condition     = length(var.name) <= 24 && length(var.name) >= 3
    error_message = "Key Vault name must be between 3 and 24 characters."
  }
}

variable "location" {
  description = "Azure region where the Key Vault will be created."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the Key Vault."
  type        = string
}

variable "subnet_private_endpoints_id" {
  description = "Resource ID of the private endpoints subnet. Used for the Key Vault private endpoint NIC."
  type        = string
}

variable "private_dns_zone_kv_id" {
  description = "Resource ID of the privatelink.vaultcore.azure.net private DNS zone."
  type        = string
}

variable "sku_name" {
  description = "SKU tier for the Key Vault. Use 'standard' for most workloads; 'premium' for HSM-backed keys."
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be 'standard' or 'premium'."
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection to prevent permanent deletion during the retention period. Set to true in production."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the Key Vault."
  type        = map(string)
  default     = {}
}
