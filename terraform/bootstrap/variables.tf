variable "project" {
  description = "Short project identifier applied to resource tags."
  type        = string
  default     = "findata"
}

variable "location" {
  description = "Azure region where the tfstate resources will be created."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the tfstate storage account."
  type        = string
  default     = "rg-findata-tfstate"
}

variable "storage_account_name" {
  description = <<-EOT
    Name of the storage account that holds Terraform state files.
    Must be globally unique, lowercase alphanumeric, 3-24 characters.
  EOT
  type        = string
  default     = "stfindatatfstate"
}

variable "container_name" {
  description = "Name of the blob container inside the storage account."
  type        = string
  default     = "tfstate"
}
