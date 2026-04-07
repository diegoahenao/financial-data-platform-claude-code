# ==============================================================================
# Snowflake Database
# ==============================================================================

resource "snowflake_database" "this" {
  name    = var.database_name
  comment = "Primary database for the ${var.environment} Financial Data Platform."
}

# ==============================================================================
# Medallion Layer Schemas
# ==============================================================================
# Landing layer resides in Azure Blob Storage — there is no LANDING schema here.
# All data enters Snowflake at the RAW schema via COPY INTO from External Stages.

resource "snowflake_schema" "raw" {
  database = snowflake_database.this.name
  name     = "RAW"
  comment  = "Exact source copies loaded via COPY INTO. No business logic. Append or full-replace only."
}

resource "snowflake_schema" "silver" {
  database = snowflake_database.this.name
  name     = "SILVER"
  comment  = "Cleaned, typed, and deduplicated data. Defensive typing (TRY_CAST, NULLIF) applied here."
}

resource "snowflake_schema" "gold" {
  database = snowflake_database.this.name
  name     = "GOLD"
  comment  = "Business-ready aggregates, metrics, and dimensional models for BI and analytics."
}
