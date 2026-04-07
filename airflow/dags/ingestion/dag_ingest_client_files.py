"""
Ingestion DAG — Azure Blob Storage → Snowflake RAW

Loads all client source files from the INBOUND_STAGE External Stage into
the five canonical RAW tables. One TaskGroup per logical entity; each group
contains a CREATE TABLE IF NOT EXISTS followed by COPY INTO statements for
each client's files.

Per CLAUDE.md:
  - catchup=False is mandatory
  - max_active_runs=1 prevents concurrent races on shared RAW tables
  - Never invoke dbt directly from an ingestion DAG
  - All COPY INTO must go through a named External Stage (no direct creds)
  - client_id is stamped as a literal constant per file batch at load time
"""

from __future__ import annotations

from datetime import timedelta

from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.utils.dates import days_ago
from airflow.utils.task_group import TaskGroup

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SNOWFLAKE_CONN_ID = "snowflake_loader"
DATABASE = "FINANCIAL_DATA"
RAW_SCHEMA = "RAW"
STAGE = f"{DATABASE}.{RAW_SCHEMA}.INBOUND_STAGE"

# Sub-paths within the stage container (inbound-files-cc/)
CLIENT_A_PATH = "client_a/"
CLIENT_C_PATH = "client_c/"

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
# Named file format DDLs
# Must exist before any COPY INTO referencing them runs.
# These are CREATE OR REPLACE so the task is idempotent.
# ---------------------------------------------------------------------------

DDL_FMT_CSV = f"""
CREATE OR REPLACE FILE FORMAT {DATABASE}.{RAW_SCHEMA}.FMT_CSV
    TYPE = 'CSV'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null')
    EMPTY_FIELD_AS_NULL = TRUE;
"""

DDL_FMT_JSON = f"""
CREATE OR REPLACE FILE FORMAT {DATABASE}.{RAW_SCHEMA}.FMT_JSON
    TYPE = 'JSON';
"""

DDL_FMT_XML = f"""
CREATE OR REPLACE FILE FORMAT {DATABASE}.{RAW_SCHEMA}.FMT_XML
    TYPE = 'XML'
    STRIP_OUTER_ELEMENT = TRUE;
"""

# ---------------------------------------------------------------------------
# DDL helpers — CREATE TABLE IF NOT EXISTS for each RAW entity
# ---------------------------------------------------------------------------

DDL_CUSTOMERS = f"""
CREATE TABLE IF NOT EXISTS {DATABASE}.{RAW_SCHEMA}.CUSTOMERS (
    client_id       VARCHAR(50)  NOT NULL,
    customer_id     VARCHAR(100),
    first_name      VARCHAR(200),
    last_name       VARCHAR(200),
    customer_name   VARCHAR(400),
    email           VARCHAR(400),
    loyalty_tier    VARCHAR(50),
    segment         VARCHAR(50),
    signup_source   VARCHAR(100),
    is_active       VARCHAR(10),
    _source_file    VARCHAR(500) NOT NULL,
    _loaded_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
"""

DDL_ORDERS = f"""
CREATE TABLE IF NOT EXISTS {DATABASE}.{RAW_SCHEMA}.ORDERS (
    client_id       VARCHAR(50)  NOT NULL,
    order_id        VARCHAR(100),
    customer_id     VARCHAR(100),
    order_date      VARCHAR(50),
    order_status    VARCHAR(50),
    channel         VARCHAR(50),
    _source_file    VARCHAR(500) NOT NULL,
    _loaded_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
"""

DDL_PRODUCTS = f"""
CREATE TABLE IF NOT EXISTS {DATABASE}.{RAW_SCHEMA}.PRODUCTS (
    client_id       VARCHAR(50)  NOT NULL,
    sku             VARCHAR(100),
    product_name    VARCHAR(400),
    category        VARCHAR(100),
    unit_price      VARCHAR(50),
    currency        VARCHAR(10),
    is_active       VARCHAR(10),
    _source_file    VARCHAR(500) NOT NULL,
    _loaded_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
"""

DDL_TRANSACTIONS = f"""
CREATE TABLE IF NOT EXISTS {DATABASE}.{RAW_SCHEMA}.TRANSACTIONS (
    client_id       VARCHAR(50)  NOT NULL,
    raw_payload     VARIANT      NOT NULL,
    _source_file    VARCHAR(500) NOT NULL,
    _loaded_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
"""

DDL_PAYMENTS = f"""
CREATE TABLE IF NOT EXISTS {DATABASE}.{RAW_SCHEMA}.PAYMENTS (
    client_id       VARCHAR(50)  NOT NULL,
    payment_id      VARCHAR(100),
    order_id        VARCHAR(100),
    payment_method  VARCHAR(50),
    amount          VARCHAR(50),
    currency        VARCHAR(10),
    status          VARCHAR(50),
    _source_file    VARCHAR(500) NOT NULL,
    _loaded_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
"""

# ---------------------------------------------------------------------------
# COPY INTO statements
# FILE_FORMAT references a named format (FORMAT_NAME) created above.
# PATTERN uses (?i) prefix for case-insensitive matching — required because
# source files arrive with mixed-case names and extensions (e.g. Customer.CSV).
# ---------------------------------------------------------------------------

COPY_CUSTOMERS_CLIENT_A = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.CUSTOMERS (
    client_id, customer_id, first_name, last_name,
    email, loyalty_tier, signup_source, is_active,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_a',
        $1, $2, $3, $4, $5, $6, $7,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_A_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*customer.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_CUSTOMERS_CLIENT_C = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.CUSTOMERS (
    client_id, customer_id, customer_name, email,
    segment, is_active,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_c',
        $1, $2, $3, $4, $5,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_C_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*customer.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_ORDERS_CLIENT_A = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.ORDERS (
    client_id, order_id, customer_id, order_date,
    order_status, channel,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_a',
        $1, $2, $3, $4, $5,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_A_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*order.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_ORDERS_CLIENT_C = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.ORDERS (
    client_id, order_id, customer_id, order_date,
    order_status,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_c',
        $1, $2, $3, $4,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_C_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*order.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_PRODUCTS_CLIENT_A = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.PRODUCTS (
    client_id, sku, product_name, category,
    unit_price, currency, is_active,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_a',
        $1, $2, $3, $4, $5, $6,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_A_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*product.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_PRODUCTS_CLIENT_C = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.PRODUCTS (
    client_id, sku, product_name, category,
    unit_price, currency, is_active,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_c',
        $1, $2, $3, $4, $5, $6,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_C_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*product.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

# XML transactions — each <Transaction> element becomes one VARIANT row
COPY_TRANSACTIONS_CLIENT_A = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.TRANSACTIONS (
    client_id, raw_payload, _source_file, _loaded_at
)
FROM (
    SELECT
        'client_a',
        $1,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_A_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_XML'),
    PATTERN => '(?i).*transaction.*\\.(xml|txt)')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

# JSON transactions — loaded as one VARIANT row per file.
# The outer JSON document is {{"client": ..., "transactions": [...]}}, not a bare array,
# so STRIP_OUTER_ARRAY is not applicable. The dbt staging model unnests the
# transactions array via LATERAL FLATTEN(input => raw_payload:transactions).
COPY_TRANSACTIONS_CLIENT_C = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.TRANSACTIONS (
    client_id, raw_payload, _source_file, _loaded_at
)
FROM (
    SELECT
        'client_c',
        $1,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_C_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_JSON'),
    PATTERN => '(?i).*transaction.*\\.json')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

COPY_PAYMENTS_CLIENT_C = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.PAYMENTS (
    client_id, payment_id, order_id, payment_method,
    amount, currency, status,
    _source_file, _loaded_at
)
FROM (
    SELECT
        'client_c',
        $1, $2, $3, $4, $5, $6,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP()
    FROM @{STAGE}/{CLIENT_C_PATH}
    (FILE_FORMAT => (FORMAT_NAME = '{DATABASE}.{RAW_SCHEMA}.FMT_CSV'),
    PATTERN => '(?i).*payment.*\\.csv')
)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;
"""

# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------

with DAG(
    dag_id="ingest_client_files",
    description="Load client files from Azure Blob Storage External Stage into Snowflake RAW tables.",
    default_args=default_args,
    schedule_interval="@daily",
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    tags=["ingestion", "raw", "client_a", "client_c"],
) as dag:

    # ── File formats (idempotent — CREATE OR REPLACE) ─────────────────────────
    # Named formats must exist before any COPY INTO runs. All three are created
    # in parallel; entity groups depend on all three completing.
    create_fmt_csv = SQLExecuteQueryOperator(
        task_id="create_fmt_csv",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=DDL_FMT_CSV,
    )
    create_fmt_json = SQLExecuteQueryOperator(
        task_id="create_fmt_json",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=DDL_FMT_JSON,
    )
    create_fmt_xml = SQLExecuteQueryOperator(
        task_id="create_fmt_xml",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=DDL_FMT_XML,
    )
    setup_formats = [create_fmt_csv, create_fmt_json, create_fmt_xml]

    # ── Customers ─────────────────────────────────────────────────────────────
    with TaskGroup("customers") as tg_customers:
        create_customers = SQLExecuteQueryOperator(
            task_id="create_raw_customers",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=DDL_CUSTOMERS,
        )
        copy_customers_a = SQLExecuteQueryOperator(
            task_id="copy_customers_client_a",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_CUSTOMERS_CLIENT_A,
        )
        copy_customers_c = SQLExecuteQueryOperator(
            task_id="copy_customers_client_c",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_CUSTOMERS_CLIENT_C,
        )
        create_customers >> [copy_customers_a, copy_customers_c]

    # ── Orders ────────────────────────────────────────────────────────────────
    with TaskGroup("orders") as tg_orders:
        create_orders = SQLExecuteQueryOperator(
            task_id="create_raw_orders",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=DDL_ORDERS,
        )
        copy_orders_a = SQLExecuteQueryOperator(
            task_id="copy_orders_client_a",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_ORDERS_CLIENT_A,
        )
        copy_orders_c = SQLExecuteQueryOperator(
            task_id="copy_orders_client_c",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_ORDERS_CLIENT_C,
        )
        create_orders >> [copy_orders_a, copy_orders_c]

    # ── Products ──────────────────────────────────────────────────────────────
    with TaskGroup("products") as tg_products:
        create_products = SQLExecuteQueryOperator(
            task_id="create_raw_products",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=DDL_PRODUCTS,
        )
        copy_products_a = SQLExecuteQueryOperator(
            task_id="copy_products_client_a",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_PRODUCTS_CLIENT_A,
        )
        copy_products_c = SQLExecuteQueryOperator(
            task_id="copy_products_client_c",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_PRODUCTS_CLIENT_C,
        )
        create_products >> [copy_products_a, copy_products_c]

    # ── Transactions ──────────────────────────────────────────────────────────
    with TaskGroup("transactions") as tg_transactions:
        create_transactions = SQLExecuteQueryOperator(
            task_id="create_raw_transactions",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=DDL_TRANSACTIONS,
        )
        copy_transactions_a = SQLExecuteQueryOperator(
            task_id="copy_transactions_client_a",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_TRANSACTIONS_CLIENT_A,
        )
        copy_transactions_c = SQLExecuteQueryOperator(
            task_id="copy_transactions_client_c",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_TRANSACTIONS_CLIENT_C,
        )
        create_transactions >> [copy_transactions_a, copy_transactions_c]

    # ── Payments (Client C only) ───────────────────────────────────────────────
    with TaskGroup("payments") as tg_payments:
        create_payments = SQLExecuteQueryOperator(
            task_id="create_raw_payments",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=DDL_PAYMENTS,
        )
        copy_payments_c = SQLExecuteQueryOperator(
            task_id="copy_payments_client_c",
            conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_PAYMENTS_CLIENT_C,
        )
        create_payments >> copy_payments_c

    # File formats must be ready before any entity group starts
    setup_formats >> [tg_customers, tg_orders, tg_products, tg_transactions, tg_payments]
