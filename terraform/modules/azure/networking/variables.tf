variable "name_prefix" {
  description = "Prefix applied to all networking resource names (e.g. findata-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain all networking resources."
  type        = string
}

variable "location" {
  description = "Azure region where networking resources will be created."
  type        = string
}

variable "vnet_address_space" {
  description = "CIDR block for the Virtual Network (e.g. 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_airflow_cidr" {
  description = "CIDR block for the Airflow worker subnet. Must fall within vnet_address_space."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_private_endpoints_cidr" {
  description = "CIDR block for the private endpoints subnet. Must fall within vnet_address_space."
  type        = string
  default     = "10.0.2.0/24"
}

variable "tags" {
  description = "Tags to apply to all networking resources."
  type        = map(string)
  default     = {}
}
