variable "environment" {
  description = "Deployment environment (dev, staging, prod). Prefixed to warehouse names."
  type        = string
}

variable "warehouse_size" {
  description = "Size of all virtual warehouses. Prod may override per-warehouse inside this module."
  type        = string
  default     = "X-SMALL"
  validation {
    condition = contains(
      ["X-SMALL", "SMALL", "MEDIUM", "LARGE", "X-LARGE"],
      var.warehouse_size
    )
    error_message = "warehouse_size must be a standard Snowflake warehouse size."
  }
}

variable "auto_suspend_seconds" {
  description = "Seconds of inactivity before a warehouse auto-suspends. Must be ≤ 300 per CLAUDE.md policy."
  type        = number
  default     = 300
  validation {
    condition     = var.auto_suspend_seconds <= 300
    error_message = "auto_suspend_seconds must not exceed 300 (5 minutes) per platform policy."
  }
}
