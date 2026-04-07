output "ingestion_warehouse_name" {
  description = "Name of the ingestion Virtual Warehouse (used by COPY INTO DAGs)."
  value       = snowflake_warehouse.ingestion.name
}

output "transformation_warehouse_name" {
  description = "Name of the transformation Virtual Warehouse (used by dbt runs)."
  value       = snowflake_warehouse.transformation.name
}

output "reporting_warehouse_name" {
  description = "Name of the reporting Virtual Warehouse (used by BI tools)."
  value       = snowflake_warehouse.reporting.name
}
