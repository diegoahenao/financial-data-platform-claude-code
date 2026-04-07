variable "storage_account_name" {
  description = <<-EOT
    Base name for the storage account. Hyphens are automatically stripped to meet
    Azure naming requirements (lowercase alphanumeric, 3-24 characters).
  EOT
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the storage account."
  type        = string
}

variable "location" {
  description = "Azure region where the storage account will be created."
  type        = string
}

variable "subnet_airflow_id" {
  description = "Resource ID of the Airflow subnet. Added to the storage account network allowlist."
  type        = string
}

variable "subnet_private_endpoints_id" {
  description = "Resource ID of the private endpoints subnet. Used for the blob private endpoint NIC."
  type        = string
}

variable "private_dns_zone_blob_id" {
  description = "Resource ID of the privatelink.blob.core.windows.net private DNS zone."
  type        = string
}

variable "landing_containers" {
  description = <<-EOT
    Map of logical source names to container configuration.
    Each entry creates one Blob Storage container and optional virtual folder
    placeholders (zero-byte .keep blobs) to represent directory paths.
    Example:
      {
        "inbound" = {
          container_name = "inbound-files-cc"
          folders        = ["client_a", "client_b"]
        }
      }
  EOT
  type = map(object({
    container_name = string
    folders        = optional(list(string), [])
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
