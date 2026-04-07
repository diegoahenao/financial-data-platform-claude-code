# ==============================================================================
# Dev environment — variable values
# Supply at init/apply time:
#   terraform -chdir=../../ apply -var-file=environments/dev/terraform.tfvars
# ==============================================================================

environment         = "dev"
location            = "eastus"
resource_group_name = "rg-financial-data-platform-cc"

# NOTE: Azure Key Vault names must be 3-24 characters.
key_vault_name             = "fin-data-platform-cc"
key_vault_purge_protection = false

storage_account_name = "stafinancialdatacc"

landing_containers = {
  "inbound" = {
    container_name = "inbound-files-cc"
    folders        = ["client_a", "client_c"]
  }
}

vnet_address_space            = "10.0.0.0/16"
subnet_airflow_cidr           = "10.0.1.0/24"
subnet_private_endpoints_cidr = "10.0.2.0/24"

log_retention_in_days = 30
alert_email_receivers = [
  { name = "data-engineering", email = "data-engineering@example.com" }
]

# RSA public key body (no -----BEGIN/END PUBLIC KEY----- headers).
# Generate keys: openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out airflow_rsa_key.p8
#                openssl rsa -in airflow_rsa_key.p8 -pubout -out airflow_rsa_key.pub
airflow_loader_rsa_public_key  = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1/BMVMxn5wyCllQRxjjtYm+5cRNfGPUyDsbXRk2szm8AOOa8qnLo5EMbSSJRsWBcoNLDu1/P7Os67td2k3yZt2Zsjtaz6It7lHSDQ8Mc09OR6ET+3Xeyx1vujd1eTeQEY1dWVuormSbzz5SDAVbwMP4mLgmvU6FiF7x4yEybpreNrgjTs2nYefuL1NADrplY114JUVT8pQt5zi5pBMK3fQixxJ874LwOgtEEzLghjXralPVnnWBJoJlE4fGMc3cCf+jcwIpnW3Iw/SEIK/025x40Q1WR0y9tyBZOV0GZESGvZ7nMxj4O1Mt529aVFnRALLQ67PNpLqdh2G7Gd6njRQIDAQAB"
dbt_transformer_rsa_public_key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAm47hOFL5Ah0pgGtbwk6Nvj9jXM7cYsqfgrHUnOn+2moPNuVOa1U1Vqy5idcseERPm4pRFChKWau/D+qSZ6kjtTXeVc+D6VSoF+/cMYbkuYILnOG6v7holIWPMDxA4FkKtkIaQzp65QV1WuytrXiV+HuO/maZLcr2reTFQNqKyWHc09jFzHuUlnEd0AuUfdmRqUDZPajzxAUIcRX3vGc0aV87nwLHDeRw/jeOujPLAVzo3VItPRRYpN/7alyB+WECdXmdiqEzKU9Kr3vKHF8TqoAP06Fd6Fv0dHFYo1U86Oa1AYbh0/Nqw1LOYS9yS+yM8i7VY209kT3lf1I8on0YEwIDAQAB"

snowflake_warehouse_size       = "X-SMALL"
snowflake_auto_suspend_seconds = 60
