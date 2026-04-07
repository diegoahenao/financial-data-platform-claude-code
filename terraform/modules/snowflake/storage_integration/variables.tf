variable "environment" {
  description = "Deployment environment (dev, staging, prod). Prefixed to the integration name."
  type        = string
}

variable "storage_account_name" {
  description = "Actual name of the Azure storage account (hyphens already stripped)."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the Azure storage account. Used to scope the Storage Blob Data Reader role assignment."
  type        = string
}

variable "container_names" {
  description = <<-EOT
    Map of logical source name to container name (as output by the blob_storage module).
    Each entry creates one External Stage pointing to that container.
    Example: { "inbound" = "inbound-files-cc" }
  EOT
  type        = map(string)
}

variable "database_name" {
  description = "Snowflake database where the External Stages will be created (in the RAW schema)."
  type        = string
}
