variable "name_prefix" {
  description = "Prefix applied to all Airflow resource names (e.g. findata-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain Airflow resources."
  type        = string
}

variable "location" {
  description = "Azure region where Airflow resources will be created."
  type        = string
}

variable "subnet_airflow_id" {
  description = "Resource ID of the Airflow subnet for VNet injection."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault. Airflow identity is granted Secrets User access."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the landing zone storage account. Airflow identity is granted Blob Data Reader access."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace for Airflow container log streaming."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all Airflow resources."
  type        = map(string)
  default     = {}
}
