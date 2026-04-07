variable "name_prefix" {
  description = "Prefix applied to all monitoring resource names (e.g. findata-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain monitoring resources."
  type        = string
}

variable "location" {
  description = "Azure region where monitoring resources will be created."
  type        = string
}

variable "retention_in_days" {
  description = "Number of days to retain logs in the Log Analytics Workspace (30-730)."
  type        = number
  default     = 30
  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "alert_email_receivers" {
  description = <<-EOT
    List of email receivers for platform alert notifications.
    Example: [{ name = "data-engineering", email = "de-team@example.com" }]
  EOT
  type = list(object({
    name  = string
    email = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all monitoring resources."
  type        = map(string)
  default     = {}
}
