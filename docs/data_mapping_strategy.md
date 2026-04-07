# Data Mapping Strategy — Silver (Staging) Layer

**Status:** Pending review  
**Author:** Data Engineering  
**Last updated:** 2026-04-06  
**Governed by:** CLAUDE.md — Pillar 2 (Defensive Typing) and Pillar 4 (Medallion Architecture)

> This document defines how every raw field from each client source file is parsed,
> cleaned, typed, and mapped into the canonical Silver layer entities.
> No dbt SQL is included here. This document must be reviewed and approved before
> any model code is written.

---

## RAW Layer Data Consolidation Standard

> **This section is a binding architectural rule.** Every design decision in this
> document must comply with it. Any proposal that violates it must be escalated and
> explicitly approved before implementation begins.

### Rule: One Table Per Entity, All Clients Combined

All source files — regardless of client — are loaded into a **single shared RAW table
per logical entity**. Creating separate tables or schemas per client is strictly
forbidden.

| Logical Entity | Canonical RAW Table | Scope |
|---|---|---|
| Transactions | `FIN_DATA_DEV.RAW.TRANSACTIONS` | All clients, all formats |
| Customers | `FIN_DATA_DEV.RAW.CUSTOMERS` | All clients |
| Orders | `FIN_DATA_DEV.RAW.ORDERS` | All clients |
| Products | `FIN_DATA_DEV.RAW.PRODUCTS` | All clients |
| Payments | `FIN_DATA_DEV.RAW.PAYMENTS` | All clients |

### Explicitly Forbidden Patterns

The following table and schema structures are **not permitted** at any layer:

```
-- FORBIDDEN: client-scoped schemas
FIN_DATA_DEV.RAW.CLIENT_A.*
FIN_DATA_DEV.RAW.CLIENT_C.*

-- FORBIDDEN: per-client tables
FIN_DATA_DEV.RAW.CLIENT_A_TRANSACTIONS
FIN_DATA_DEV.RAW.TRANSACTIONS_CLIENT_C

-- FORBIDDEN: client-specific staging models
FIN_DATA_DEV.SILVER.STG_CLIENT_A_CUSTOMERS
```

### Required: `client_id` as the Mandatory Partitioning Key

Every RAW table and every Silver staging model must include a `client_id` column.
This is the sole mechanism for partitioning, filtering, and attributing rows to their
source client. It must be:

- **Populated at load time** — stamped by the Airflow `COPY INTO` DAG, not derived
  later in dbt. The DAG sets `client_id` as a literal constant per file batch
  (e.g. `'client_a'`, `'client_c'`).
- **Non-nullable** — a RAW row without a `client_id` must be rejected at ingestion.
- **Lowercase and snake_case** — `'client_a'`, `'client_c'`, never `'ClientA'` or `'CLIENT_C'`.
- **Indexed** (via Snowflake clustering key where table size justifies it) — all
  queries against RAW tables must filter on `client_id` first.

### `client_id` Values

| Client | `client_id` Value | Source File Pattern |
|---|---|---|
| Client A | `'client_a'` | `ClientA_Transactions_*.xml`, `Customer.csv`, `Orders.csv`, `Products.csv` |
| Client C | `'client_c'` | `transactions.json`, `Customer.CSV`, `Order.csv`, `Payments.csv`, `Product.csv` |

### Why This Rule Exists

Separate per-client tables create compounding maintenance problems as new clients are
onboarded: duplicated dbt models, duplicated tests, duplicated Airflow DAGs, and no
ability to write cross-client analytics without `UNION ALL` chains. A single table per
entity with `client_id` as the discriminator scales to any number of clients with zero
structural change.

---

## 1. Source Inventory

Two clients deliver data. Each uses different file formats and schemas.

### 1.1 Client A — Source Files

| File | Format | Logical Entity | RAW Table (shared) | `client_id` stamped |
|---|---|---|---|---|
| `ClientA_Transactions_1.xml` | XML (nested) | Transactions + Items + Payment | `FIN_DATA_DEV.RAW.TRANSACTIONS` | `'client_a'` |
| `ClientA_Transactions_4.txt` | XML (continuation) | Transactions + Items + Payment | `FIN_DATA_DEV.RAW.TRANSACTIONS` | `'client_a'` |
| `Customer.csv` | CSV | Customers | `FIN_DATA_DEV.RAW.CUSTOMERS` | `'client_a'` |
| `Orders.csv` | CSV | Orders | `FIN_DATA_DEV.RAW.ORDERS` | `'client_a'` |
| `Products.csv` | CSV | Products | `FIN_DATA_DEV.RAW.PRODUCTS` | `'client_a'` |

> Both XML files share the same `<SalesData>` structure and are appended into the
> same `FIN_DATA_DEV.RAW.TRANSACTIONS` table by the Airflow `COPY INTO` DAG.
> The DAG stamps `client_id = 'client_a'` on every row at load time.

### 1.2 Client C — Source Files

| File | Format | Logical Entity | RAW Table (shared) | `client_id` stamped |
|---|---|---|---|---|
| `transactions.json` | JSON (nested array) | Transactions + Items + Payment | `FIN_DATA_DEV.RAW.TRANSACTIONS` | `'client_c'` |
| `Customer.CSV` | CSV | Customers | `FIN_DATA_DEV.RAW.CUSTOMERS` | `'client_c'` |
| `Order.csv` | CSV | Orders | `FIN_DATA_DEV.RAW.ORDERS` | `'client_c'` |
| `Payments.csv` | CSV | Payments | `FIN_DATA_DEV.RAW.PAYMENTS` | `'client_c'` |
| `Product.csv` | CSV | Products | `FIN_DATA_DEV.RAW.PRODUCTS` | `'client_c'` |

> Client C provides payments as a standalone file; Client A embeds payment data
> inside each transaction record. Both are consolidated into `FIN_DATA_DEV.RAW.PAYMENTS`
> and unified into a single `stg_payments` Silver entity. The `source_type` column
> within the table distinguishes the originating file format.

---

## 2. Anomaly Inventory

All intentional and observed anomalies across every source file, catalogued before writing any cleaning logic.

### 2.1 Anomalies — Client A Transactions (XML)

| Transaction | Anomaly Type | Detail |
|---|---|---|
| TXN-1001 | Duplicate | Exact duplicate of the full transaction |
| TXN-1001 (dup) | Structural drift | Uses `<LastLastName>` instead of `<LastName>` |
| TXN-1001 | Negative quantity | `SKU-A-002`: `Quantity = -1` |
| TXN-1002 | Empty primary key | `<TransactionID>` is empty string |
| TXN-1002 | Missing date | `<OrderDate>` is empty |
| TXN-1002 | Missing email | `<Email>` is empty |
| TXN-1002 | Empty SKU | `<SKU>` is empty |
| TXN-1002 | Zero price / amount | `UnitPrice = 0`, `Amount = 0` |
| TXN-1003 | Unexpected nested field | `<Customer><Metadata>` block not in schema |
| TXN-1003 | Negative quantity | `SKU-A-004`: `Quantity = -2` |
| TXN-1004 | Missing email | `<Email>` is empty |
| TXN-1004 | Unexpected nested field | `<Customer><Tags>` block |
| TXN-1016 | Missing email | `<Email>` is empty |
| TXN-1016 | Unexpected nested field | `<Customer><Notes>` block |
| TXN-1017 | Empty SKU | `<SKU>` is empty |
| TXN-1017 | Negative payment amount | `Amount = -49.99` |
| TXN-1018 | Unexpected nested field | `<Customer><Tags>` block |
| TXN-1019 | Missing date | `<OrderDate>` is empty |
| TXN-1019 | Negative quantity | `SKU-A-018`: `Quantity = -3` |
| TXN-1020 | Unexpected nested field | `<Item><Warranty>` block |
| TXN-1021 | Duplicate | Exact duplicate of the full transaction |

### 2.2 Anomalies — Client A Customers (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| CUST-A-0003 | Missing field | `loyalty_tier` is empty |
| CUST-A-0004 | Missing fields | `first_name`, `last_name`, `email` all empty |
| CUST-A-0004 | Sentinel value | `last_name = "Unknown"` |
| CUST-A-0005 | Invalid email | `cevans@example` — missing TLD |
| CUST-A-0008 | Missing field | `loyalty_tier` is empty |
| CUST-A-0011 | Missing field | `loyalty_tier` is empty |
| CUST-A-0015 | Missing field | `email` is empty |
| CUST-A-0017 | Missing field | `loyalty_tier` is empty |
| CUST-A-0001 (last row) | Duplicate | Exact duplicate of first row |
| CUST-A-0033 | Invalid email | `jchen@@example..com` — double `@`, double `.` |
| CUST-A-0040 | Null-heavy row | Only `customer_id` and `is_active=false`; all name/email fields empty |

### 2.3 Anomalies — Client A Orders (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| ORD-5004 | Referential integrity | `customer_id = CUST-A-9999` does not exist in customers |
| ORD-5005 | Missing date | `order_date` is empty |
| ORD-5008 | Missing date | `order_date` is empty |
| ORD-5019 | Missing date | `order_date` is empty |
| ORD-5001 (last row) | Duplicate | Exact duplicate of first row |

### 2.4 Anomalies — Client A Products (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| SKU-A-011 | Negative price | `unit_price = -9.99` |
| SKU-A-003 (last rows) | Duplicate | Exact duplicate |
| SKU-A-999 | Sentinel / anomaly row | `product_name = "Unknown Product"`, `unit_price = 0.00`, `is_active = false` |

### 2.5 Anomalies — Client C Transactions (JSON)

| Record | Anomaly Type | Detail |
|---|---|---|
| C-TXN-3001 | Duplicate | Exact duplicate transaction ID |
| C-TXN-3001 (dup) | Empty items array | `"items": []` — no line items |
| C-TXN-3003 | Negative quantity | `qty = -3` |
| C-TXN-3004 | Null date | `"date": null` |
| C-TXN-3005 | Null order ID | `"order.id": null` |
| C-TXN-3006 | Empty customer name | `"name": ""` |
| C-TXN-3006 | Invalid email | `"noemail@"` — no domain |
| C-TXN-3007 | Zero quantity | `qty = 0` |
| C-TXN-3007 | Zero payment total | `total = 0.00` |
| C-TXN-3008 | Invalid customer | `C-CUST-9999` not in customers |
| C-TXN-3008 | Unknown SKU | `C-SKU-999` sentinel product |
| C-TXN-3008 | Zero price | `amount = 0.00` |
| (noted in comments) | Inconsistent nesting | Presence of `metadata`, `tags`, `shipping` fields varies per record |

### 2.6 Anomalies — Client C Customers (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| C-CUST-5006 | Missing name | `customer_name` is empty |
| C-CUST-5006 | Invalid email | `noemail@` — no domain |
| C-CUST-5010 | Sentinel segment | `segment = "UNKNOWN"` |
| C-CUST-5013 | Missing email | `email` is empty |
| C-CUST-5020 | Invalid email | `jchen@@example..com` |
| C-CUST-5001 (last row) | Duplicate | Exact duplicate |
| C-CUST-5099 | Null-heavy row | All fields empty except `customer_id` and `is_active = false` |

### 2.7 Anomalies — Client C Orders (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| C-ORD-9004 | Missing date | `order_date` is empty |
| C-ORD-9008 | Referential integrity | `customer_id = C-CUST-9999` does not exist |
| C-ORD-9019 | Missing date | `order_date` is empty |
| C-ORD-9001 (last row) | Duplicate | Exact duplicate |

### 2.8 Anomalies — Client C Payments (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| PAY-C-0005 | Negative amount | `amount = -10.00`, status = `REFUNDED` |
| PAY-C-0007 | Zero amount | `amount = 0.00`, status = `SETTLED` (suspicious) |
| PAY-C-0008 | Zero amount | `amount = 0.00`, status = `SETTLED` (suspicious) |
| PAY-C-0017 | Negative amount | `amount = -49.99`, status = `REFUNDED` |
| PAY-C-0001 (last row) | Duplicate | Exact duplicate |

### 2.9 Anomalies — Client C Products (CSV)

| Row | Anomaly Type | Detail |
|---|---|---|
| C-SKU-003 (last rows) | Duplicate | Exact duplicate |
| C-SKU-999 | Sentinel / anomaly row | `product_name = "Unknown Product"`, `unit_price = 0.00` |
| C-SKU-011 | Negative price | `unit_price = -59.99` |

---

## 3. Canonical Silver Entity Model

The Silver layer exposes **six canonical entities** that represent every client's data
in a unified structure. All entities carry audit columns and data quality flags.

```
stg_customers         — one row per unique customer per client
stg_orders            — one row per unique order per client
stg_products          — one row per unique SKU per client
stg_transactions      — one row per unique transaction per client
stg_transaction_items — one row per line item (unnested from transactions)
stg_payments          — one row per payment event per client
```

### 3.1 Schema Differences That Drive the Canonical Design

| Dimension | Client A | Client C | Canonical Resolution |
|---|---|---|---|
| Customer name format | `first_name` + `last_name` (separate columns) | `customer_name` (single combined field) | Store both `first_name`, `last_name`, and `full_name`; derive missing parts |
| Customer tier vocabulary | `loyalty_tier`: GOLD, SILVER, BRONZE, PLATINUM | `segment`: VIP, REGULAR, NEW, UNKNOWN | Preserve source value; add `canonical_customer_tier` (see §4.1) |
| Order channel | `channel` present | No `channel` field | `channel` nullable; NULL for Client C |
| Transaction format | XML (nested `<Items>`, `<Payment>`) | JSON (nested `items[]`, `payment`) | Parsed and flattened identically in Silver |
| Items quantity field name | `Quantity` | `qty` | Mapped to `quantity` |
| Payment source | Embedded in transaction XML | Embedded in transaction JSON **and** standalone `Payments.csv` | `stg_payments` unified from both sources; `source_type` column distinguishes them |
| Customer ID prefix | `CUST-A-` | `C-CUST-` | Preserved as `source_customer_id`; `client_id` column provides partitioning |
| SKU prefix | `SKU-A-` | `C-SKU-` | Preserved as `source_sku` |

---

## 4. Field-Level Mapping Tables

### Conventions Used in This Section

| Symbol | Meaning |
|---|---|
| `TRY_CAST(x AS T)` | Safe cast; returns NULL on failure instead of raising an error |
| `NULLIF(x, v)` | Replace sentinel value `v` with NULL |
| `NULLIF(TRIM(x), '')` | Collapse whitespace-only strings to NULL |
| `REGEXP_LIKE(x, p)` | Returns boolean; used to produce a quality flag, not to drop rows |
| `ROW_NUMBER() OVER (PARTITION BY … ORDER BY _loaded_at)` | Deduplication; rank = 1 is the surviving row |
| `[CLIENT_A]` / `[CLIENT_C]` | Which client the source column comes from |

---

### 4.1 `stg_customers`

**Source table:** `FIN_DATA_DEV.RAW.CUSTOMERS` — filtered by `client_id`

**Deduplication key:** `(client_id, source_customer_id)`

| Canonical Column | Type | Client A Source Column | Client C Source Column | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `customer_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_customer_id'])` |
| `client_id` | VARCHAR | `'client_a'` (literal) | `'client_c'` (literal) | Constant; identifies origin |
| `source_customer_id` | VARCHAR | `customer_id` | `customer_id` | `NULLIF(TRIM(customer_id), '')` |
| `first_name` | VARCHAR | `first_name` | Derived from `customer_name` | Client A: `NULLIF(TRIM(first_name), '')`. Client C: `NULLIF(TRIM(SPLIT_PART(customer_name, ' ', 1)), '')` |
| `last_name` | VARCHAR | `last_name` | Derived from `customer_name` | Client A: `NULLIF(NULLIF(TRIM(last_name), ''), 'Unknown')`. Client C: `NULLIF(TRIM(SPLIT_PART(customer_name, ' ', 2)), '')` |
| `full_name` | VARCHAR | Derived | `customer_name` | Client A: `NULLIF(TRIM(CONCAT_WS(' ', first_name, last_name)), '')`. Client C: `NULLIF(TRIM(customer_name), '')` |
| `email` | VARCHAR | `email` | `email` | `NULLIF(TRIM(email), '')` — preserves invalid format; validity is flagged separately |
| `email_is_valid` | BOOLEAN | Derived | Derived | `REGEXP_LIKE(email, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$')`. NULL email → FALSE |
| `source_customer_tier` | VARCHAR | `loyalty_tier` | `segment` | `NULLIF(NULLIF(TRIM(UPPER(loyalty_tier)), ''), 'UNKNOWN')` |
| `canonical_customer_tier` | VARCHAR | Derived | Derived | See tier mapping table below |
| `signup_source` | VARCHAR | `signup_source` | NULL | Client A: `NULLIF(TRIM(signup_source), '')`. Client C: NULL (field absent) |
| `is_active` | BOOLEAN | `is_active` | `is_active` | `TRY_CAST(TRIM(is_active) AS BOOLEAN)` — NULL on parse failure |
| `_is_duplicate` | BOOLEAN | Derived | Derived | `ROW_NUMBER() OVER (PARTITION BY client_id, source_customer_id ORDER BY _loaded_at) > 1` |
| `_source_file` | VARCHAR | — | — | Snowflake `METADATA$FILENAME` at load time |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Canonical customer tier mapping:**

| Source (Client A `loyalty_tier`) | Source (Client C `segment`) | `canonical_customer_tier` |
|---|---|---|
| GOLD | VIP | HIGH |
| PLATINUM | VIP | HIGH |
| SILVER | REGULAR | MEDIUM |
| BRONZE | NEW | LOW |
| NULL / empty | NULL / UNKNOWN | NULL |

**Rows excluded from Silver promotion (quarantined):**
- `source_customer_id IS NULL` — no primary key; row cannot be identified.

**Rows retained with quality flags set:**
- Invalid email → `email_is_valid = FALSE`, row kept.
- Missing tier → `canonical_customer_tier = NULL`, row kept.
- Duplicate → `_is_duplicate = TRUE`, row kept but excluded from Gold by default.

---

### 4.2 `stg_orders`

**Source table:** `FIN_DATA_DEV.RAW.ORDERS` — filtered by `client_id`

**Deduplication key:** `(client_id, source_order_id)`

| Canonical Column | Type | Client A Source | Client C Source | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `order_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_order_id'])` |
| `client_id` | VARCHAR | `'client_a'` | `'client_c'` | Constant |
| `source_order_id` | VARCHAR | `order_id` | `order_id` | `NULLIF(TRIM(order_id), '')` |
| `source_customer_id` | VARCHAR | `customer_id` | `customer_id` | `NULLIF(TRIM(customer_id), '')` |
| `order_date` | DATE | `order_date` | `order_date` | `TRY_CAST(TRIM(order_date) AS DATE)` — NULL on empty or unparseable value |
| `order_date_is_missing` | BOOLEAN | Derived | Derived | `order_date IS NULL` |
| `order_status` | VARCHAR | `order_status` | `order_status` | `NULLIF(TRIM(UPPER(order_status)), '')` |
| `channel` | VARCHAR | `channel` | NULL | Client A: `NULLIF(TRIM(channel), '')`. Client C: NULL |
| `customer_ref_is_valid` | BOOLEAN | Derived | Derived | Populated in a post-join dbt test (`relationships`); not set inline at staging |
| `_is_duplicate` | BOOLEAN | Derived | Derived | `ROW_NUMBER() OVER (PARTITION BY client_id, source_order_id ORDER BY _loaded_at) > 1` |
| `_source_file` | VARCHAR | — | — | `METADATA$FILENAME` |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Rows excluded from Silver promotion (quarantined):**
- `source_order_id IS NULL`.

**Rows retained with quality flags set:**
- Missing `order_date` → `order_date IS NULL`, `order_date_is_missing = TRUE`, row kept.
- Orphaned `source_customer_id` (e.g. `CUST-A-9999`) → flagged by dbt `relationships` test; row kept.

---

### 4.3 `stg_products`

**Source table:** `FIN_DATA_DEV.RAW.PRODUCTS` — filtered by `client_id`

**Deduplication key:** `(client_id, source_sku)`

| Canonical Column | Type | Client A Source | Client C Source | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `product_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_sku'])` |
| `client_id` | VARCHAR | `'client_a'` | `'client_c'` | Constant |
| `source_sku` | VARCHAR | `sku` | `sku` | `NULLIF(TRIM(sku), '')` |
| `product_name` | VARCHAR | `product_name` | `product_name` | `NULLIF(NULLIF(TRIM(product_name), ''), 'Unknown Product')` |
| `category` | VARCHAR | `category` | `category` | `NULLIF(NULLIF(TRIM(UPPER(category)), ''), 'UNKNOWN')` |
| `unit_price` | NUMBER(12,2) | `unit_price` | `unit_price` | `TRY_CAST(unit_price AS NUMBER(12,2))` |
| `unit_price_is_valid` | BOOLEAN | Derived | Derived | `unit_price IS NOT NULL AND unit_price > 0` |
| `currency` | VARCHAR(3) | `currency` | `currency` | `NULLIF(TRIM(UPPER(currency)), '')` — expected `'USD'` |
| `is_active` | BOOLEAN | `is_active` | `is_active` | `TRY_CAST(TRIM(is_active) AS BOOLEAN)` |
| `_is_duplicate` | BOOLEAN | Derived | Derived | `ROW_NUMBER() OVER (PARTITION BY client_id, source_sku ORDER BY _loaded_at) > 1` |
| `_source_file` | VARCHAR | — | — | `METADATA$FILENAME` |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Rows excluded from Silver promotion (quarantined):**
- `source_sku IS NULL`.

**Rows retained with quality flags set:**
- Negative or zero `unit_price` → `unit_price_is_valid = FALSE`, row kept (may be a credit/return SKU).
- Sentinel product (`Unknown Product`, price 0) → `product_name = NULL` after NULLIF, `unit_price_is_valid = FALSE`, row kept.

---

### 4.4 `stg_transactions`

**Source table:** `FIN_DATA_DEV.RAW.TRANSACTIONS` — filtered by `client_id`

**Deduplication key:** `(client_id, source_transaction_id)`

> **RAW storage note:** `FIN_DATA_DEV.RAW.TRANSACTIONS` holds a `raw_payload VARIANT`
> column that stores the unparsed document for each row, plus the mandatory `client_id`
> and `_source_file` columns stamped at load time. Client A XML files are loaded with
> `FILE_FORMAT TYPE = XML`; each `<Transaction>` element becomes one row. Client C JSON
> files use `FILE_FORMAT TYPE = JSON` with `STRIP_OUTER_ARRAY = TRUE`, producing one row
> per transaction object from the `transactions` array. The `client_id` column is what
> tells downstream dbt models which parsing path (XMLGET vs JSON GET) to apply — XML rows
> use `XMLGET(raw_payload, 'TransactionID')` syntax; JSON rows use
> `raw_payload:id::STRING` syntax. Both are resolved in the Silver model via
> `CASE WHEN client_id = 'client_a' THEN ... ELSE ... END` branching.

| Canonical Column | Type | Client A XML Path | Client C JSON Path | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `transaction_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_transaction_id'])` |
| `client_id` | VARCHAR | `'client_a'` | `'client_c'` | Constant |
| `source_transaction_id` | VARCHAR | `//TransactionID` | `$.id` | `NULLIF(TRIM(value), '')` |
| `source_order_id` | VARCHAR | `//Order/OrderID` | `$.order.id` | `NULLIF(TRIM(value), '')` |
| `source_customer_id` | VARCHAR | `//Order/Customer/CustomerID` | `$.order.customer.id` | `NULLIF(TRIM(value), '')` |
| `order_date` | DATE | `//Order/OrderDate` | `$.order.date` | `TRY_CAST(TRIM(value) AS DATE)` |
| `order_date_is_missing` | BOOLEAN | Derived | Derived | `order_date IS NULL` |
| `customer_first_name` | VARCHAR | `//Customer/Name/FirstName` | `SPLIT_PART($.order.customer.name, ' ', 1)` | `NULLIF(TRIM(value), '')` |
| `customer_last_name` | VARCHAR | `//Customer/Name/LastName` | `SPLIT_PART($.order.customer.name, ' ', 2)` | `NULLIF(TRIM(value), '')`. Client A note: fall back to `<LastLastName>` when `<LastName>` is absent (structural drift in TXN-1001 duplicate) |
| `customer_email` | VARCHAR | `//Customer/Email` | `$.order.customer.email` | `NULLIF(TRIM(value), '')` |
| `customer_email_is_valid` | BOOLEAN | Derived | Derived | `REGEXP_LIKE(customer_email, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$')` |
| `payment_method` | VARCHAR | `//Payment/Method` | `$.payment.method` | `NULLIF(TRIM(value), '')` |
| `payment_amount` | NUMBER(12,2) | `//Payment/Amount` | `$.payment.total` | `TRY_CAST(value AS NUMBER(12,2))` |
| `payment_amount_is_valid` | BOOLEAN | Derived | Derived | `payment_amount IS NOT NULL AND payment_amount >= 0` — negative flagged but not dropped (may be refund) |
| `payment_currency` | VARCHAR(3) | `//Payment/Amount/@currency` | Inferred `'USD'` (not present at payment level in JSON) | `NULLIF(TRIM(UPPER(value)), '')` |
| `has_line_items` | BOOLEAN | Derived | Derived | `TRUE` if at least one item was parsed; `FALSE` for empty `<Items>` or `"items": []` |
| `_is_duplicate` | BOOLEAN | Derived | Derived | `ROW_NUMBER() OVER (PARTITION BY client_id, source_transaction_id ORDER BY _loaded_at) > 1` |
| `_source_file` | VARCHAR | — | — | `METADATA$FILENAME` |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Rows excluded from Silver promotion (quarantined):**
- `source_transaction_id IS NULL` — cannot be identified or deduplicated.

**Rows retained with quality flags set:**
- Negative `payment_amount` → `payment_amount_is_valid = FALSE`, row kept.
- Missing `order_date` → `order_date IS NULL`, row kept.
- Empty `items` array → `has_line_items = FALSE`, row kept.
- Invalid customer email → `customer_email_is_valid = FALSE`, row kept.

**Client A XML structural drift note:**  
TXN-1001's duplicate record uses `<LastLastName>` instead of `<LastName>`. The staging
model must check for `<LastName>` first and fall back to `<LastLastName>` before applying
`NULLIF`. Unexpected child nodes (`<Metadata>`, `<Tags>`, `<Notes>`, `<Warranty>`, `<Fees>`)
are silently ignored during extraction — they are not mapped to any Silver column.

---

### 4.5 `stg_transaction_items`

**Source table:** `FIN_DATA_DEV.RAW.TRANSACTIONS` — same table as `stg_transactions`; items are unnested from the `raw_payload VARIANT` column, filtered by `client_id`.

**Grain:** One row per `(client_id, source_transaction_id, sku)` combination after unnesting.

**Deduplication key:** `(client_id, source_transaction_id, sku)` — if the same SKU appears
twice in one transaction, flag the second occurrence.

| Canonical Column | Type | Client A XML Path | Client C JSON Path | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `item_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_transaction_id', 'source_sku'])` |
| `client_id` | VARCHAR | `'client_a'` | `'client_c'` | Constant |
| `source_transaction_id` | VARCHAR | Parent `//TransactionID` | Parent `$.id` | `NULLIF(TRIM(value), '')` |
| `source_sku` | VARCHAR | `//Item/SKU` | `$.items[*].sku` | `NULLIF(TRIM(value), '')` |
| `item_description` | VARCHAR | `//Item/Description` | `$.items[*].description` | `NULLIF(TRIM(value), '')` |
| `quantity` | INTEGER | `//Item/Quantity` | `$.items[*].qty` | `TRY_CAST(value AS INTEGER)` |
| `quantity_is_valid` | BOOLEAN | Derived | Derived | `quantity IS NOT NULL AND quantity > 0` — zero and negative flagged |
| `unit_price` | NUMBER(12,2) | `//Item/UnitPrice` | `$.items[*].price.amount` | `TRY_CAST(value AS NUMBER(12,2))` |
| `unit_price_is_valid` | BOOLEAN | Derived | Derived | `unit_price IS NOT NULL AND unit_price > 0` |
| `currency` | VARCHAR(3) | `//Item/UnitPrice/@currency` | `$.items[*].price.currency` | `NULLIF(TRIM(UPPER(value)), '')` |
| `line_total` | NUMBER(12,2) | Derived | Derived | `CASE WHEN quantity_is_valid AND unit_price_is_valid THEN quantity * unit_price ELSE NULL END` — not computed on invalid inputs |
| `_source_file` | VARCHAR | — | — | `METADATA$FILENAME` |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Rows excluded from Silver promotion (quarantined):**
- `source_transaction_id IS NULL` or `source_sku IS NULL` — line cannot be attributed.

**Rows retained with quality flags set:**
- Negative or zero `quantity` → `quantity_is_valid = FALSE`, `line_total = NULL`.
- Negative or zero `unit_price` → `unit_price_is_valid = FALSE`, `line_total = NULL`.

> `<Item><Warranty>` sub-elements (TXN-1020) are silently ignored — not mapped.

---

### 4.6 `stg_payments`

**Source tables:**
- `FIN_DATA_DEV.RAW.PAYMENTS` — Client C standalone payment records (CSV), filtered by `client_id = 'client_c'`
- `FIN_DATA_DEV.RAW.TRANSACTIONS` — Client A payment data extracted from XML payload; Client C payment totals also present in JSON payload as a cross-reference, filtered by `client_id`

**Deduplication key:**
- Client C CSV rows: `(client_id, source_payment_id)`
- Client A rows (derived from transactions): `(client_id, source_transaction_id)` — one payment per transaction record
- Cross-source deduplication for Client C (CSV vs JSON): deduplicated on `(client_id, source_order_id)`; see Open Question #4

| Canonical Column | Type | Client A Source | Client C CSV Source | Transformation / Cleaning Rule |
|---|---|---|---|---|
| `payment_sk` | VARCHAR | — | — | `dbt_utils.generate_surrogate_key(['client_id', 'source_payment_id'])` |
| `client_id` | VARCHAR | `'client_a'` | `'client_c'` | Constant |
| `source_payment_id` | VARCHAR | Derived: `'TXN-' \|\| source_transaction_id` | `payment_id` | Client A has no standalone payment ID; synthesize from transaction |
| `source_order_id` | VARCHAR | `//Order/OrderID` | `order_id` | `NULLIF(TRIM(value), '')` |
| `payment_method` | VARCHAR | `//Payment/Method` | `payment_method` | `NULLIF(TRIM(value), '')` |
| `amount` | NUMBER(12,2) | `//Payment/Amount` | `amount` | `TRY_CAST(value AS NUMBER(12,2))` |
| `amount_is_valid` | BOOLEAN | Derived | Derived | `amount IS NOT NULL AND amount >= 0` |
| `is_refund` | BOOLEAN | Derived | Derived | `amount < 0 OR UPPER(status) = 'REFUNDED'` |
| `currency` | VARCHAR(3) | `//Payment/Amount/@currency` | `currency` | `NULLIF(TRIM(UPPER(value)), '')` |
| `status` | VARCHAR | NULL (not in XML) | `status` | Client A: NULL. Client C: `NULLIF(TRIM(UPPER(status)), '')` |
| `processing_fee` | NUMBER(12,2) | `//Payment/Fees/ProcessingFee` | NULL | Client A only: `TRY_CAST(value AS NUMBER(12,2))`. Client C: NULL |
| `source_type` | VARCHAR | `'transaction_xml'` | `'payments_csv'` | Constant; identifies which raw table this row originated from |
| `_is_duplicate` | BOOLEAN | Derived | Derived | `ROW_NUMBER() OVER (PARTITION BY client_id, source_payment_id ORDER BY _loaded_at) > 1` |
| `_source_file` | VARCHAR | — | — | `METADATA$FILENAME` |
| `_loaded_at` | TIMESTAMP_TZ | — | — | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` |

**Rows excluded from Silver promotion (quarantined):**
- `source_order_id IS NULL`.

**Rows retained with quality flags set:**
- Negative `amount` → `amount_is_valid = FALSE`, `is_refund = TRUE`, row kept.
- Zero `amount` with `status = 'SETTLED'` → `amount_is_valid = FALSE` (suspicious), row kept.

---

## 5. Deduplication Strategy

All staging models follow the same pattern. Duplicates are **never deleted** at Silver —
they are flagged and excluded downstream.

```
Pattern:
  ROW_NUMBER() OVER (
      PARTITION BY <dedup_key_columns>
      ORDER BY _loaded_at ASC   -- earliest load wins
  ) AS _row_num

Silver model filters: WHERE _row_num = 1
_is_duplicate = (_row_num > 1)  -- written before the filter for auditability
```

**Deduplication keys per entity:**

| Entity | Deduplication Key |
|---|---|
| `stg_customers` | `(client_id, source_customer_id)` |
| `stg_orders` | `(client_id, source_order_id)` |
| `stg_products` | `(client_id, source_sku)` |
| `stg_transactions` | `(client_id, source_transaction_id)` |
| `stg_transaction_items` | `(client_id, source_transaction_id, source_sku)` |
| `stg_payments` | `(client_id, source_payment_id)` |

---

## 6. Data Quality Flag Conventions

Every quality concern is surfaced as a boolean flag column rather than silently
dropping or correcting data. This preserves auditability and lets Gold-layer models
or BI consumers decide how to handle edge cases.

| Flag Column | Meaning When TRUE |
|---|---|
| `_is_duplicate` | Row is a duplicate of an earlier-loaded record with the same key |
| `email_is_valid` | Email passes the regex pattern check |
| `order_date_is_missing` | `order_date` could not be parsed or was empty |
| `quantity_is_valid` | `quantity` is a positive integer |
| `unit_price_is_valid` | `unit_price` is a positive number |
| `amount_is_valid` | Payment `amount` is non-negative |
| `is_refund` | Payment amount is negative or status indicates a refund |
| `has_line_items` | Transaction has at least one parsed line item |
| `customer_email_is_valid` | Email embedded in transaction passes the regex pattern check |

**Quarantine (rows excluded entirely from Silver):**  
A separate `QUARANTINE` schema will hold rows rejected for having no usable primary key.
These are not lost — they remain in RAW and in the quarantine table for investigation.

| Entity | Quarantine Condition |
|---|---|
| `stg_customers` | `source_customer_id IS NULL` |
| `stg_orders` | `source_order_id IS NULL` |
| `stg_products` | `source_sku IS NULL` |
| `stg_transactions` | `source_transaction_id IS NULL` |
| `stg_transaction_items` | `source_transaction_id IS NULL OR source_sku IS NULL` |
| `stg_payments` | `source_order_id IS NULL` |

---

## 7. Audit Columns (All Entities)

Every Silver model includes these columns, sourced at load time:

| Column | Type | Value |
|---|---|---|
| `_source_file` | VARCHAR | `METADATA$FILENAME` — the Blob Storage path of the originating file |
| `_loaded_at` | TIMESTAMP_TZ | `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)` at the time of the `COPY INTO` |
| `_dbt_updated_at` | TIMESTAMP_TZ | Set by dbt at model execution time |

---

## 8. Resolved Decisions

| # | Decision | Resolution |
|---|---|---|
| R1 | **Per-client table isolation** | **Closed — forbidden.** All clients load into a single shared table per entity in `FIN_DATA_DEV.RAW`. Client-scoped schemas (`RAW.CLIENT_A.*`) and per-client tables are explicitly prohibited. `client_id` is the mandatory partitioning key on every table. See the RAW Layer Data Consolidation Standard above. |
| R2 | **XML loading mechanism** | **Closed — VARIANT + XMLGET.** XML files are loaded into `FIN_DATA_DEV.RAW.TRANSACTIONS` as a `raw_payload VARIANT` column alongside `client_id` and `_source_file`. Parsing happens in the dbt Silver model via `XMLGET` / `GET`, branched on `client_id`. No Airflow pre-processing step. |

---

## 9. Open Questions — Pending Decision Before Implementation

The following points require a business or architecture decision before dbt models are written.

| # | Question | Options | Owner |
|---|---|---|---|
| 1 | **Tier harmonization level**: Should canonical tier mapping (HIGH / MEDIUM / LOW) happen in Silver or Gold? Silver simplifies Gold but couples business meaning into the staging layer. | (a) Map in Silver. (b) Preserve raw tiers in Silver; map in Gold mart. | Business / Data Lead |
| 2 | **Negative payment amounts**: Are negative amounts always refunds, or can they be adjustments / credit memos? The `is_refund` flag currently uses `amount < 0 OR status = 'REFUNDED'`. | (a) Keep current logic. (b) Only trust the `status` column. (c) Add a separate `payment_type` enum. | Business |
| 3 | **Zero-amount payments**: PAY-C-0007 and PAY-C-0008 have `amount = 0.00` with `status = SETTLED`. Should these be quarantined or flagged? | (a) Flag only (`amount_is_valid = FALSE`). (b) Quarantine. | Business |
| 4 | **Client C payment deduplication**: Payment data exists in both `Payments.csv` and `transactions.json`. Should both be loaded into `stg_payments` (deduplicated by `source_order_id`) or should one source take precedence? | (a) Load both; dedup on order_id. (b) `Payments.csv` is authoritative; ignore JSON totals. | Architecture |
| 5 | **Orphaned order rows**: Orders referencing non-existent customers (e.g. `CUST-A-9999`) — should these be quarantined at Silver or allowed through and caught only by dbt `relationships` test? | (a) Flag only; let test catch it. (b) Quarantine. | Architecture |
| 6 | **Client B**: The business requirements mention a third client format (the `.txt` file appears to be a continuation of Client A's XML). Is there a distinct Client B source? If so, its schema is not yet available. Once confirmed, its `client_id` value must be agreed before any DAG or model is written. | Confirm scope | Project Lead |
