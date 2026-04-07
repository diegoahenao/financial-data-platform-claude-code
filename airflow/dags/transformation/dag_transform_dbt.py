"""
Transformation DAG — dbt run + dbt test (SILVER → GOLD)

Waits for the ingestion DAG to complete, then runs all dbt staging and mart
models, executes the full test suite, and checks source freshness.

Per CLAUDE.md:
  - catchup=False is mandatory
  - max_active_runs=1 prevents concurrent dbt runs on shared schemas
  - Never issue COPY INTO from a transformation DAG
  - Uses ExternalTaskSensor to wait for ingestion before starting
  - Passes {{ ds }} as run_date so dbt models can use time-context macros
  - Datetime.now() must never be used — use Airflow macros instead

Credential setup:
  SNOWFLAKE_DBT_PRIVATE_KEY   — RSA private key PEM (set via Key Vault /
                                 Container App secret env var)
  SNOWFLAKE_ORGANIZATION_NAME — Snowflake org name
  SNOWFLAKE_ACCOUNT_NAME      — Snowflake account name
  Both are available as environment variables injected by the Container App.
  The setup task writes the key to /tmp/snowflake_dbt_key.p8 and constructs
  SNOWFLAKE_ACCOUNT before any dbt command runs.
"""

from __future__ import annotations

from datetime import timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.dates import days_ago

# ---------------------------------------------------------------------------
# Configuration
# DBT_TARGET can be overridden per environment via Airflow Variable
# "dbt_target" without redeploying the DAG.
# ---------------------------------------------------------------------------
DBT_PROJECT_DIR   = "/opt/airflow/dbt"
DBT_PROFILES_DIR  = "/opt/airflow/dbt"
DBT_TARGET        = Variable.get("dbt_target", default_var="staging")
DBT_KEY_PATH      = "/tmp/snowflake_dbt_key.p8"

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
DBT_CMD = (
    f"dbt"
    f" --project-dir {DBT_PROJECT_DIR}"
    f" --profiles-dir {DBT_PROFILES_DIR}"
    f" --target {DBT_TARGET}"
)

# ---------------------------------------------------------------------------
# Credential setup script — runs once before any dbt command
# Writes the RSA private key to disk and constructs SNOWFLAKE_ACCOUNT.
# Each subsequent dbt task sources /tmp/dbt_env.sh to inherit these vars.
# ---------------------------------------------------------------------------
SETUP_CREDENTIALS = """
set -e
echo "$SNOWFLAKE_DBT_PRIVATE_KEY" > {{ params.key_path }}
chmod 600 {{ params.key_path }}
echo "export SNOWFLAKE_ACCOUNT=${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}" \
    > /tmp/dbt_env.sh
"""

# Prefix sourced by every dbt task to pick up SNOWFLAKE_ACCOUNT
SOURCE_ENV = "source /tmp/dbt_env.sh && "

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
    tags=["transformation", "silver", "gold", "dbt"],
    params={"key_path": DBT_KEY_PATH},
) as dag:

    # ── Wait for ingestion to complete ────────────────────────────────────────
    # Waits for the full ingest_client_files DAG to succeed on the same
    # logical execution date before running any transformation.
    wait_for_ingestion = ExternalTaskSensor(
        task_id="wait_for_ingestion",
        external_dag_id="ingest_client_files",
        external_task_id=None,         # None = wait for whole DAG
        execution_delta=timedelta(0),  # same execution date
        timeout=3600,                  # 1 hour max wait
        poke_interval=60,
        mode="reschedule",             # releases worker slot while waiting
    )

    # ── Write private key + build SNOWFLAKE_ACCOUNT ───────────────────────────
    setup_credentials = BashOperator(
        task_id="setup_credentials",
        bash_command=SETUP_CREDENTIALS,
    )

    # ── Install / update dbt packages ─────────────────────────────────────────
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"{SOURCE_ENV}{DBT_CMD} deps",
    )

    # ── Check source freshness (RAW tables) ───────────────────────────────────
    # Warns if RAW tables have not been updated within the freshness thresholds
    # defined in sources.yml. Runs before dbt run so stale data is surfaced.
    dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"{SOURCE_ENV}{DBT_CMD} source freshness",
    )

    # ── dbt run — Silver (staging models) ─────────────────────────────────────
    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"{SOURCE_ENV}{DBT_CMD} run"
            f" --select staging"
            """ --vars '{"run_date": "{{ ds }}"}'"""
        ),
    )

    # ── dbt run — Gold (mart models) ──────────────────────────────────────────
    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            f"{SOURCE_ENV}{DBT_CMD} run"
            f" --select marts"
            """ --vars '{"run_date": "{{ ds }}"}'"""
        ),
    )

    # ── dbt test — full test suite ────────────────────────────────────────────
    # Tests all models (Silver + Gold). Failures here alert data-engineering
    # but do not roll back the run — downstream consumers see the data with
    # warning annotations via dbt test severity settings.
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"{SOURCE_ENV}{DBT_CMD} test"
            """ --vars '{"run_date": "{{ ds }}"}'"""
        ),
    )

    # ── Pipeline order ────────────────────────────────────────────────────────
    (
        wait_for_ingestion
        >> setup_credentials
        >> dbt_deps
        >> dbt_source_freshness
        >> dbt_run_staging
        >> dbt_run_marts
        >> dbt_test
    )
