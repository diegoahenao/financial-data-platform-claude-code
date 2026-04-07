variable "database_name" {
  description = "Name of the Snowflake database. Used to scope all schema and object grants."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
}

variable "airflow_loader_rsa_public_key" {
  description = <<-EOT
    RSA public key for the AIRFLOW_LOADER service account (PEM body without headers).
    Generate with: openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8
    Store the private key in Azure Key Vault; pass only the public key here.
  EOT
  type        = string
  sensitive   = false
}

variable "dbt_transformer_rsa_public_key" {
  description = <<-EOT
    RSA public key for the DBT_TRANSFORMER service account (PEM body without headers).
    Generate with: openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8
    Store the private key in Azure Key Vault; pass only the public key here.
  EOT
  type        = string
  sensitive   = false
}
