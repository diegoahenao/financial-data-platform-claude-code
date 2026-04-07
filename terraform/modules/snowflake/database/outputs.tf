output "database_name" {
  description = "Name of the provisioned Snowflake database."
  value       = snowflake_database.this.name
}

output "schema_raw" {
  description = "Name of the RAW schema."
  value       = snowflake_schema.raw.name
}

output "schema_silver" {
  description = "Name of the SILVER schema."
  value       = snowflake_schema.silver.name
}

output "schema_gold" {
  description = "Name of the GOLD schema."
  value       = snowflake_schema.gold.name
}
