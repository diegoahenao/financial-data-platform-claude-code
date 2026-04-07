# ==============================================================================
# Prod environment — variable values
# ==============================================================================

environment         = "prod"
location            = "eastus"
resource_group_name = "rg-financial-data-platform-cc-prod"

key_vault_name             = "fin-data-platform-prod"
key_vault_purge_protection = true # mandatory in production

storage_account_name = "stafinancialdataprod"

landing_containers = {
  "inbound" = {
    container_name = "inbound-files-prod"
    folders        = ["client_a", "client_c"]
  }
}

vnet_address_space            = "10.1.0.0/16"
subnet_airflow_cidr           = "10.1.1.0/24"
subnet_private_endpoints_cidr = "10.1.2.0/24"

log_retention_in_days = 90 # longer retention in prod
alert_email_receivers = [
  { name = "data-engineering", email = "data-engineering@example.com" }
]

# RSA public key body (no -----BEGIN/END PUBLIC KEY----- headers).
airflow_loader_rsa_public_key  = "REPLACE_WITH_PROD_AIRFLOW_LOADER_PUBLIC_KEY_BODY"
dbt_transformer_rsa_public_key = "REPLACE_WITH_PROD_DBT_TRANSFORMER_PUBLIC_KEY_BODY"

snowflake_warehouse_size       = "SMALL" # larger than dev
snowflake_auto_suspend_seconds = 300
