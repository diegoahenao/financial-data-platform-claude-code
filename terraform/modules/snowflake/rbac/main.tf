# ==============================================================================
# Roles — principle of least privilege per CLAUDE.md
# ==============================================================================

resource "snowflake_account_role" "loader" {
  name    = "LOADER"
  comment = "Raw ingestion only. Used by Airflow DAGs to execute COPY INTO on the RAW schema."
}

resource "snowflake_account_role" "transformer" {
  name    = "TRANSFORMER"
  comment = "dbt transformations. Reads from RAW, writes to SILVER and GOLD."
}

resource "snowflake_account_role" "reporter" {
  name    = "REPORTER"
  comment = "Read-only access to the GOLD schema for BI tools and analysts."
}

# ==============================================================================
# Database-level grants
# ==============================================================================

# always_apply = true forces the provider to re-issue the GRANT on every apply.
# This guards against the Snowflake provider v0.98 known issue where a grant
# is recorded in Terraform state but not actually executed in Snowflake.
resource "snowflake_grant_privileges_to_account_role" "loader_db_usage" {
  account_role_name = snowflake_account_role.loader.name
  privileges        = ["USAGE"]
  always_apply      = true
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_db_usage" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]
  always_apply      = true
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# dbt runs CREATE SCHEMA IF NOT EXISTS before executing models.
# Without CREATE SCHEMA on the database, Snowflake returns 003001
# "Insufficient privileges to operate on database" even if USAGE is present.
resource "snowflake_grant_privileges_to_account_role" "transformer_db_create_schema" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["CREATE SCHEMA"]
  always_apply      = true
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "reporter_db_usage" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["USAGE"]
  always_apply      = true
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# ==============================================================================
# Schema-level grants — LOADER (RAW only)
# ==============================================================================

resource "snowflake_grant_privileges_to_account_role" "loader_raw_schema" {
  account_role_name = snowflake_account_role.loader.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE STAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"RAW\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "loader_raw_future_tables" {
  account_role_name = snowflake_account_role.loader.name
  privileges        = ["INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

# Covers tables that already existed before the FUTURE grant was first applied.
resource "snowflake_grant_privileges_to_account_role" "loader_raw_all_tables" {
  account_role_name = snowflake_account_role.loader.name
  privileges        = ["INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

# ==============================================================================
# Schema-level grants — TRANSFORMER (RAW read + SILVER/GOLD write)
# ==============================================================================

resource "snowflake_grant_privileges_to_account_role" "transformer_raw_schema" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"RAW\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_raw_future_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

# Covers RAW tables that already existed before the FUTURE grant was first applied.
resource "snowflake_grant_privileges_to_account_role" "transformer_raw_all_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_silver_schema" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"SILVER\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_silver_future_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"SILVER\""
    }
  }
}

# Covers SILVER tables created in a prior run (dbt incremental re-runs).
resource "snowflake_grant_privileges_to_account_role" "transformer_silver_all_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"SILVER\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_gold_schema" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"GOLD\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_gold_future_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# Covers GOLD tables created in a prior run.
resource "snowflake_grant_privileges_to_account_role" "transformer_gold_all_tables" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# ==============================================================================
# Schema-level grants — REPORTER (GOLD read-only)
# ==============================================================================

resource "snowflake_grant_privileges_to_account_role" "reporter_gold_schema" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["USAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"GOLD\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "reporter_gold_future_tables" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# Covers GOLD tables created before this grant was first applied.
resource "snowflake_grant_privileges_to_account_role" "reporter_gold_all_tables" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "reporter_gold_future_views" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# Covers GOLD views created before this grant was first applied.
resource "snowflake_grant_privileges_to_account_role" "reporter_gold_all_views" {
  account_role_name = snowflake_account_role.reporter.name
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# ==============================================================================
# Schema-level grants — SYSADMIN (full read on all schemas for admins)
# ==============================================================================
# SYSADMIN owns the FINANCIAL_DATA database but not the schemas/tables within
# it — those are owned by TRANSFORMER (created by dbt). Without explicit grants,
# ACCOUNTADMIN (which inherits SYSADMIN) cannot SELECT from SILVER or GOLD.
# These grants allow any human admin using ACCOUNTADMIN/SYSADMIN to query all
# layers for debugging and operations.

resource "snowflake_grant_privileges_to_account_role" "sysadmin_raw_schema" {
  account_role_name = "SYSADMIN"
  privileges        = ["USAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"RAW\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_raw_all_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_raw_future_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"RAW\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_silver_schema" {
  account_role_name = "SYSADMIN"
  privileges        = ["USAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"SILVER\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_silver_all_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"SILVER\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_silver_future_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"SILVER\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_gold_schema" {
  account_role_name = "SYSADMIN"
  privileges        = ["USAGE"]
  always_apply      = true
  on_schema {
    schema_name = "\"${var.database_name}\".\"GOLD\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_gold_all_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_gold_future_tables" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_gold_all_views" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  always_apply      = true
  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_gold_future_views" {
  account_role_name = "SYSADMIN"
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${var.database_name}\".\"GOLD\""
    }
  }
}

# ==============================================================================
# Service Account Users
# ==============================================================================
# Both users authenticate via RSA key pairs — no passwords per CLAUDE.md policy.
# Public keys are supplied as variables; private keys live in Azure Key Vault.

resource "snowflake_user" "airflow_loader" {
  name           = "AIRFLOW_LOADER"
  login_name     = "AIRFLOW_LOADER"
  comment        = "Service account for Airflow ingestion DAGs. Assigned LOADER role."
  default_role   = snowflake_account_role.loader.name
  rsa_public_key = var.airflow_loader_rsa_public_key

  lifecycle {
    ignore_changes = [password]
  }
}

resource "snowflake_user" "dbt_transformer" {
  name           = "DBT_TRANSFORMER"
  login_name     = "DBT_TRANSFORMER"
  comment        = "Service account for dbt transformation runs. Assigned TRANSFORMER role."
  default_role   = snowflake_account_role.transformer.name
  rsa_public_key = var.dbt_transformer_rsa_public_key

  lifecycle {
    ignore_changes = [password]
  }
}

# ==============================================================================
# Role → User assignments
# ==============================================================================

resource "snowflake_grant_account_role" "loader_to_airflow" {
  role_name = snowflake_account_role.loader.name
  user_name = snowflake_user.airflow_loader.name
}

resource "snowflake_grant_account_role" "transformer_to_dbt" {
  role_name = snowflake_account_role.transformer.name
  user_name = snowflake_user.dbt_transformer.name
}
