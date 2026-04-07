"""
Transformation DAG — dbt run + dbt test (SILVER → GOLD)

Triggers after the ingestion DAG completes. Runs all dbt staging and mart
models, then executes the full dbt test suite.

Per CLAUDE.md:
  - catchup=False is mandatory
  - max_active_runs=1 prevents concurrent dbt runs on shared schemas
  - Never issue COPY INTO from a transformation DAG
  - Uses dbt ExternalTaskSensor to wait for ingestion before starting
  - Passes {{ ds }} as run_date var so models can use time-context macros
"""

from __future__ import annotations

from datetime import timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.dates import days_ago

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DBT_PROJECT_DIR = "/opt/airflow/dbt"
DBT_PROFILES_DIR = "/opt/airflow/dbt"
DBT_TARGET = "staging"

# ---------------------------------------------------------------------------
# Default args — per CLAUDE.md DAG configuration defaults
# ---------------------------------------------------------------------------
default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": True,
}

# ---------------------------------------------------------------------------
# Shared dbt command prefix
# ---------------------------------------------------------------------------
DBT_CMD_PREFIX = (
    f"dbt --no-write-json"
    f" --project-dir {DBT_PROJECT_DIR}"
    f" --profiles-dir {DBT_PROFILES_DIR}"
    f" --target {DBT_TARGET}"
)

# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------

with DAG(
    dag_id="transform_dbt",
    description="Run dbt staging and mart models, then execute dbt tests (SILVER → GOLD).",
    default_args=default_args,
    schedule_interval="@daily",
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    tags=["transformation", "silver", "gold"],
) as dag:

    # ── Wait for ingestion to complete ────────────────────────────────────────
    wait_for_ingestion = ExternalTaskSensor(
        task_id="wait_for_ingestion",
        external_dag_id="ingest_client_files",
        external_task_id=None,          # None = wait for the whole DAG to succeed
        execution_delta=timedelta(0),   # same logical execution date
        timeout=3600,                   # 1 hour max wait
        poke_interval=60,
        mode="reschedule",              # releases worker slot while waiting
    )

    # ── Install dbt packages (idempotent) ─────────────────────────────────────
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=(
            f"{DBT_CMD_PREFIX} deps"
        ),
    )

    # ── dbt run — staging models (Silver layer) ───────────────────────────────
    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"{DBT_CMD_PREFIX} run"
            f" --select staging"
            f" --vars '{{\"run_date\": \"{{{{ ds }}}}\"}}'",
        ),
    )

    # ── dbt run — mart models (Gold layer) ────────────────────────────────────
    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            f"{DBT_CMD_PREFIX} run"
            f" --select marts"
            f" --vars '{{\"run_date\": \"{{{{ ds }}}}\"}}'",
        ),
    )

    # ── dbt test — full test suite ────────────────────────────────────────────
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"{DBT_CMD_PREFIX} test"
            f" --vars '{{\"run_date\": \"{{{{ ds }}}}\"}}'",
        ),
    )

    # ── dbt source freshness check ────────────────────────────────────────────
    dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=(
            f"{DBT_CMD_PREFIX} source freshness"
        ),
    )

    # ── Pipeline order ────────────────────────────────────────────────────────
    (
        wait_for_ingestion
        >> dbt_deps
        >> dbt_source_freshness
        >> dbt_run_staging
        >> dbt_run_marts
        >> dbt_test
    )
