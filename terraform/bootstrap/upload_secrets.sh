#!/usr/bin/env bash
# ==============================================================================
# upload_secrets.sh — Upload private keys to Azure Key Vault
# ==============================================================================
# Run this AFTER terraform apply has provisioned the Key Vault.
#
# Usage:
#   chmod +x upload_secrets.sh
#   ./upload_secrets.sh
# ==============================================================================

set -euo pipefail

VAULT_NAME="fin-data-platform-cc"
KEYS_DIR="$HOME/.keys"

echo "Uploading secrets to Key Vault: $VAULT_NAME"

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "snowflake-airflow-loader-private-key" \
  --file "$KEYS_DIR/airflow_loader_rsa_key.p8" \
  --output none
echo "  [OK] snowflake-airflow-loader-private-key"

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "snowflake-dbt-transformer-private-key" \
  --file "$KEYS_DIR/dbt_transformer_rsa_key.p8" \
  --output none
echo "  [OK] snowflake-dbt-transformer-private-key"

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "snowflake-terraform-private-key" \
  --file "$KEYS_DIR/snowflake_terraform_rsa_key.p8" \
  --output none
echo "  [OK] snowflake-terraform-private-key"

echo ""
echo "All secrets uploaded. Verify with:"
echo "  az keyvault secret list --vault-name $VAULT_NAME --query '[].name' -o tsv"
