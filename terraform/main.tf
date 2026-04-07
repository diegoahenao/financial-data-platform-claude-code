locals {
  name_prefix = "${var.project}-${var.environment}"

  default_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }

  # Merge caller-supplied tags; caller values take precedence.
  tags = merge(local.default_tags, var.tags)
}

# ==============================================================================
# Azure — Resource Group
# ==============================================================================
# All platform resources are provisioned inside this resource group.
# Created first; every other module depends on it.

module "resource_group" {
  source = "./modules/azure/resource_group"

  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# ==============================================================================
# Azure — Networking
# ==============================================================================
# Provisions the VNet, subnets, NSGs, and private DNS zones.
# Must be created before any resource that exposes a private endpoint.

module "networking" {
  source = "./modules/azure/networking"

  name_prefix                   = local.name_prefix
  resource_group_name           = module.resource_group.name
  location                      = module.resource_group.location
  vnet_address_space            = var.vnet_address_space
  subnet_airflow_cidr           = var.subnet_airflow_cidr
  subnet_private_endpoints_cidr = var.subnet_private_endpoints_cidr
  tags                          = local.tags

  depends_on = [module.resource_group]
}

# ==============================================================================
# Azure — Key Vault
# ==============================================================================
# Central secret store for Snowflake credentials, service principal keys,
# and any other runtime secrets. Accessed via Azure Managed Identity.

module "key_vault" {
  source = "./modules/azure/key_vault"

  name                        = var.key_vault_name
  location                    = module.resource_group.location
  resource_group_name         = module.resource_group.name
  purge_protection_enabled    = var.key_vault_purge_protection
  subnet_private_endpoints_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_kv_id      = module.networking.private_dns_zone_kv_id
  tags                        = local.tags

  depends_on = [module.networking]
}

# ==============================================================================
# Azure — Blob Storage (Landing Zone)
# ==============================================================================
# Creates the storage account, containers, virtual folder placeholders,
# and a private endpoint so all blob traffic stays within the VNet.

module "blob_storage" {
  source = "./modules/azure/blob_storage"

  storage_account_name        = var.storage_account_name
  resource_group_name         = module.resource_group.name
  location                    = module.resource_group.location
  landing_containers          = var.landing_containers
  subnet_airflow_id           = module.networking.subnet_airflow_id
  subnet_private_endpoints_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_blob_id    = module.networking.private_dns_zone_blob_id
  tags                        = local.tags

  depends_on = [module.networking]
}

# ==============================================================================
# Azure — Monitoring (Log Analytics + Action Group)
# ==============================================================================
# Central observability sink. Must be created before Airflow so the Container
# App Environment can stream logs to the workspace from day one.

module "monitoring" {
  source = "./modules/azure/monitoring"

  name_prefix           = local.name_prefix
  resource_group_name   = module.resource_group.name
  location              = module.resource_group.location
  retention_in_days     = var.log_retention_in_days
  alert_email_receivers = var.alert_email_receivers
  tags                  = local.tags

  depends_on = [module.resource_group]
}

# ==============================================================================
# Azure — Airflow (Managed Identity + Container App Environment)
# ==============================================================================
# Provisions the Airflow runtime identity and VNet-injected compute environment.
# Role assignments give Airflow access to Key Vault secrets and Blob Storage.

module "airflow" {
  source = "./modules/azure/airflow"

  name_prefix                = local.name_prefix
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  subnet_airflow_id          = module.networking.subnet_airflow_id
  key_vault_id               = module.key_vault.id
  storage_account_id         = module.blob_storage.storage_account_id
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags

  depends_on = [module.networking, module.key_vault, module.blob_storage, module.monitoring]
}

# ==============================================================================
# Snowflake — Database and Schemas
# ==============================================================================
# Creates the primary database and the Medallion layer schemas:
# RAW, SILVER, GOLD (Landing resides in Azure Blob, not Snowflake).

module "snowflake_database" {
  source = "./modules/snowflake/database"

  database_name = var.snowflake_database
  environment   = var.environment
}

# ==============================================================================
# Snowflake — RBAC
# ==============================================================================
# Provisions roles (LOADER, TRANSFORMER, REPORTER) and their grants.
# Must be applied after the database so that schema-level grants resolve.

module "snowflake_rbac" {
  source = "./modules/snowflake/rbac"

  database_name                  = var.snowflake_database
  environment                    = var.environment
  airflow_loader_rsa_public_key  = var.airflow_loader_rsa_public_key
  dbt_transformer_rsa_public_key = var.dbt_transformer_rsa_public_key

  depends_on = [module.snowflake_database]
}

# ==============================================================================
# Snowflake — Virtual Warehouses
# ==============================================================================
# Separate warehouses for ingestion (COPY INTO), transformation (dbt), and
# reporting to prevent resource contention. All warehouses auto-suspend.

module "snowflake_warehouses" {
  source = "./modules/snowflake/warehouses"

  environment          = var.environment
  warehouse_size       = var.snowflake_warehouse_size
  auto_suspend_seconds = var.snowflake_auto_suspend_seconds

  depends_on = [module.snowflake_rbac]
}

# ==============================================================================
# Snowflake — Storage Integration and External Stages
# ==============================================================================
# Grants Snowflake scoped read access to Azure Blob Storage via a managed
# identity (no shared-access keys). Creates one named External Stage per
# landing container so that Airflow DAGs can issue COPY INTO commands.

module "snowflake_storage_integration" {
  source = "./modules/snowflake/storage_integration"

  storage_account_name = module.blob_storage.storage_account_name
  storage_account_id   = module.blob_storage.storage_account_id
  container_names      = module.blob_storage.container_names
  database_name        = var.snowflake_database
  environment          = var.environment
  depends_on           = [module.blob_storage, module.snowflake_rbac]
}
