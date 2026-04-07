# ==============================================================================
# Global
# ==============================================================================

variable "environment" {
  description = "Deployment environment. Controls naming, sizing, and protection rules."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  description = "Short project identifier used as a prefix in all resource names."
  type        = string
  default     = "findata"
}

# ==============================================================================
# Azure
# ==============================================================================

variable "location" {
  description = "Azure region for all resources (e.g. eastus, westeurope)."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group that hosts all platform resources."
  type        = string
}

variable "tags" {
  description = "Additional Azure resource tags merged with the default tag set."
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Azure — Networking
# ==============================================================================

variable "vnet_address_space" {
  description = "CIDR block for the platform Virtual Network."
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

# ==============================================================================
# Azure — Monitoring
# ==============================================================================

variable "log_retention_in_days" {
  description = "Number of days to retain logs in the Log Analytics Workspace."
  type        = number
  default     = 30
}

variable "alert_email_receivers" {
  description = "List of email receivers for platform alert notifications."
  type = list(object({
    name  = string
    email = string
  }))
  default = []
}

# ==============================================================================
# Azure — Key Vault
# ==============================================================================

variable "key_vault_name" {
  description = "Globally unique name for the Azure Key Vault. Must be 3-24 characters."
  type        = string
}

variable "key_vault_purge_protection" {
  description = "Enable purge protection on the Key Vault. Should be true in production."
  type        = bool
  default     = false
}

# ==============================================================================
# Azure — Blob Storage / Landing Zone
# ==============================================================================

variable "storage_account_name" {
  description = <<-EOT
    Base name for the Azure storage account. Hyphens are stripped automatically
    to comply with Azure naming rules (lowercase alphanumeric, 3-24 characters).
  EOT
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

# ==============================================================================
# Snowflake — Connection
# ==============================================================================

variable "snowflake_tf_role" {
  description = <<-EOT
    Snowflake role assumed by the Terraform service account.
    This role must have SYSADMIN and SECURITYADMIN privileges to provision
    databases, schemas, warehouses, roles, and grants.
    Value is passed directly to the provider; all other connection parameters
    (account, user, private key) must be set via environment variables.
  EOT
  type        = string
  default     = "ACCOUNTADMIN"
}

# ==============================================================================
# Snowflake — Database
# ==============================================================================

variable "snowflake_database" {
  description = "Name of the primary Snowflake database for the platform."
  type        = string
  default     = "FINANCIAL_DATA"
}

# ==============================================================================
# Snowflake — Warehouses
# ==============================================================================

variable "airflow_loader_rsa_public_key" {
  description = <<-EOT
    RSA public key (PEM body, no headers) for the AIRFLOW_LOADER Snowflake service account.
    Generate: openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8 && openssl rsa -in rsa_key.p8 -pubout | grep -v 'PUBLIC KEY'
    Store the private key in Azure Key Vault; only the public key goes here.
  EOT
  type        = string
}

variable "dbt_transformer_rsa_public_key" {
  description = <<-EOT
    RSA public key (PEM body, no headers) for the DBT_TRANSFORMER Snowflake service account.
    Generate: openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8 && openssl rsa -in rsa_key.p8 -pubout | grep -v 'PUBLIC KEY'
    Store the private key in Azure Key Vault; only the public key goes here.
  EOT
  type        = string
}

variable "snowflake_warehouse_size" {
  description = <<-EOT
    Default Virtual Warehouse size for non-prod environments.
    Prod sizing is defined per-warehouse inside the warehouses module.
  EOT
  type        = string
  default     = "X-SMALL"
  validation {
    condition = contains(
      ["X-SMALL", "SMALL", "MEDIUM", "LARGE", "X-LARGE"],
      var.snowflake_warehouse_size
    )
    error_message = "snowflake_warehouse_size must be a standard Snowflake warehouse size."
  }
}

variable "snowflake_private_key_path" {
  description = "Filesystem path to the Snowflake Terraform service account RSA private key (.p8). In CI this file is written to /tmp/snowflake_tf_key.p8 before terraform init."
  type        = string
  default     = "/tmp/snowflake_tf_key.p8"
}

variable "snowflake_auto_suspend_seconds" {
  description = "Seconds of inactivity before a Virtual Warehouse auto-suspends. Must be ≤ 300 (5 min) per CLAUDE.md policy."
  type        = number
  default     = 300
  validation {
    condition     = var.snowflake_auto_suspend_seconds <= 300
    error_message = "auto_suspend_seconds must not exceed 300 (5 minutes) per platform policy."
  }
}
