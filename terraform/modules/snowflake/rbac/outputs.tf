output "role_loader" {
  description = "Name of the LOADER role."
  value       = snowflake_account_role.loader.name
}

output "role_transformer" {
  description = "Name of the TRANSFORMER role."
  value       = snowflake_account_role.transformer.name
}

output "role_reporter" {
  description = "Name of the REPORTER role."
  value       = snowflake_account_role.reporter.name
}

output "user_airflow_loader" {
  description = "Name of the AIRFLOW_LOADER service account."
  value       = snowflake_user.airflow_loader.name
}

output "user_dbt_transformer" {
  description = "Name of the DBT_TRANSFORMER service account."
  value       = snowflake_user.dbt_transformer.name
}
