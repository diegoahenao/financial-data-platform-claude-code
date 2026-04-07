# ==============================================================================
# Virtual Warehouses — one per workload type
# ==============================================================================
# Separate warehouses prevent resource contention between ingestion, dbt runs,
# and BI queries. All warehouses auto-suspend per CLAUDE.md policy (≤ 5 min).

resource "snowflake_warehouse" "ingestion" {
  name           = "${upper(var.environment)}_INGESTION_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = var.auto_suspend_seconds
  auto_resume    = true
  comment        = "Used exclusively by Airflow COPY INTO DAGs to load data into the RAW schema."

  # Prevent concurrent ingestion runs from queuing on the same warehouse.
  max_cluster_count = 1
  min_cluster_count = 1
}

resource "snowflake_warehouse" "transformation" {
  name           = "${upper(var.environment)}_TRANSFORMATION_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = var.auto_suspend_seconds
  auto_resume    = true
  comment        = "Used exclusively by dbt runs to transform data from RAW → SILVER → GOLD."

  max_cluster_count = 1
  min_cluster_count = 1
}

resource "snowflake_warehouse" "reporting" {
  name           = "${upper(var.environment)}_REPORTING_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = var.auto_suspend_seconds
  auto_resume    = true
  comment        = "Used by BI tools and analysts querying the GOLD schema."

  max_cluster_count = 1
  min_cluster_count = 1
}

# ==============================================================================
# Warehouse grants
# ==============================================================================

resource "snowflake_grant_privileges_to_account_role" "loader_ingestion_wh" {
  account_role_name = "LOADER"
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_transformation_wh" {
  account_role_name = "TRANSFORMER"
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.transformation.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "reporter_reporting_wh" {
  account_role_name = "REPORTER"
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.reporting.name
  }
}
