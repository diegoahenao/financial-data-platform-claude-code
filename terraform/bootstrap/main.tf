# ==============================================================================
# Terraform State Backend Bootstrap
# ==============================================================================
# This workspace is a ONE-TIME prerequisite. It creates the Azure storage
# account that holds the remote state for the main Terraform workspace.
#
# Run this BEFORE running the main workspace:
#
#   cd bootstrap/
#   terraform init          # uses local state — no backend needed here
#   terraform apply
#
# After apply, initialise the main workspace with the output values:
#
#   cd ../
#   terraform init \
#     -backend-config="resource_group_name=$(terraform -chdir=bootstrap output -raw resource_group_name)" \
#     -backend-config="storage_account_name=$(terraform -chdir=bootstrap output -raw storage_account_name)" \
#     -backend-config="container_name=$(terraform -chdir=bootstrap output -raw container_name)" \
#     -backend-config="key=<environment>.terraform.tfstate"
#
# Auth: az login (developer) or ARM_* env vars (CI/CD).
# ==============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Intentionally no backend block — bootstrap state is stored locally.
  # Commit the resulting terraform.tfstate only in a secured, private location
  # or manage it manually. Do NOT commit it to this repository.
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# Resource group — isolated from the platform RG so it survives platform
# destroy/recreate cycles.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project    = var.project
    managed_by = "terraform-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# Storage account — holds all Terraform state files.
# GRS replication protects state against regional outages.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"

  # State files contain sensitive resource metadata — block all public access.
  allow_nested_items_to_be_public = false

  # Blob versioning — allows recovery of a previous state version if a plan
  # corrupts the state file.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  # Prevent accidental deletion of the state storage account.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    project    = var.project
    managed_by = "terraform-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# Container — one container holds state files for all environments.
# Each environment uses a different blob key (<env>.terraform.tfstate).
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# dbt artifacts container — stores the production manifest.json used by
# slim CI (dbt build --select state:modified+) in pull request workflows.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "dbt_artifacts" {
  name                  = "dbt-artifacts"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
