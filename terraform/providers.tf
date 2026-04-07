terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.98"
    }
  }

  # Remote state in Azure Blob Storage with state locking.
  # Values are intentionally left empty here and must be supplied at init time
  # via -backend-config flags or a backend config file. No secrets in source.
  #
  # Example:
  #   terraform init \
  #     -backend-config="resource_group_name=rg-tfstate" \
  #     -backend-config="storage_account_name=stfindata tfstate" \
  #     -backend-config="container_name=tfstate" \
  #     -backend-config="key=<environment>.terraform.tfstate"
  #
  # Authentication uses ARM_CLIENT_ID / ARM_USE_OIDC or a Managed Identity —
  # never a storage access key committed to this repository.
  backend "azurerm" {}
}

# ---------------------------------------------------------------------------
# Azure provider
# ---------------------------------------------------------------------------
# Credentials are resolved from the environment at runtime — never hardcoded.
# Supported auth methods (in precedence order):
#   1. Azure Managed Identity (recommended for CI/CD and Azure-hosted runners)
#   2. Environment variables: ARM_CLIENT_ID, ARM_CLIENT_SECRET,
#      ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
#   3. Azure CLI session (developer workstations only)
provider "azurerm" {
  features {
    key_vault {
      # Prevent accidental deletion of Key Vault secrets managed by Terraform.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      # Require explicit removal of all resources before destroying a group.
      prevent_deletion_if_contains_resources = true
    }
  }
}

# ---------------------------------------------------------------------------
# Azure AD provider
# ---------------------------------------------------------------------------
# Shares authentication with the azurerm provider (ARM_* env vars or az login).
# Used to look up Snowflake's managed service principal after the storage
# integration is created, so we can assign it the Storage Blob Data Reader role.
provider "azuread" {}

# ---------------------------------------------------------------------------
# Snowflake provider (v0.98+)
# ---------------------------------------------------------------------------
# All connection parameters are sourced from environment variables — no values
# are hardcoded here. Required environment variables:
#
#   SNOWFLAKE_ORGANIZATION_NAME  — Snowflake org name (left part of account URL)
#   SNOWFLAKE_ACCOUNT_NAME       — Snowflake account name (right part of account URL)
#   SNOWFLAKE_USER               — service account username (TERRAFORM_SVC)
#   SNOWFLAKE_PRIVATE_KEY_PATH   — path to the RSA private key file (.p8)
#
# To find org/account: Snowflake UI → bottom-left account menu → account identifier
# Format: <ORGANIZATION_NAME>-<ACCOUNT_NAME>  (split on the first hyphen)
#
# authenticator = "JWT" is required to activate private key authentication.
# Without it the provider defaults to password auth and fails.
provider "snowflake" {
  role          = var.snowflake_tf_role
  authenticator = "JWT"
}
