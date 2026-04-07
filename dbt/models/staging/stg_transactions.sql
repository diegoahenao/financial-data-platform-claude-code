{{ config(unique_key='transaction_sk') }}

-- =============================================================================
-- stg_transactions — Silver layer
-- One row per unique transaction per client, parsed from VARIANT raw_payload.
--
-- Sources:
--   Client A: XML loaded via FILE_FORMAT TYPE=XML  → raw_payload VARIANT
--   Client C: JSON loaded via FILE_FORMAT TYPE=JSON → raw_payload VARIANT
--
-- XML parsing uses XMLGET / GET_PATH. JSON uses colon notation.
-- Anomalies handled:
--   - Duplicates: deduped by (client_id, source_transaction_id)
--   - Empty transaction IDs → NULL (results in null surrogate key, excluded downstream)
--   - Missing order_date: flagged with order_date_is_missing = true
--   - Invalid emails: flagged, not dropped
--   - Negative payment amounts: flagged with payment_amount_is_valid = false
-- =============================================================================

with

raw_source as (
    select * from {{ source('raw', 'TRANSACTIONS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

-- Client A: one <Transaction> per row via STRIP_OUTER_ELEMENT = TRUE at ingest
client_a_rows as (
    select client_id, _source_file, _loaded_at, raw_payload
    from raw_source
    where client_id = 'client_a'
),

-- Client C: entire JSON doc loaded as one VARIANT row per file.
-- The outer structure is {"client": ..., "transactions": [...]}, so we must
-- unnest the transactions array here to get one row per transaction.
client_c_rows as (
    select
        s.client_id,
        s._source_file,
        s._loaded_at,
        f.value as raw_payload
    from raw_source s,
        lateral flatten(input => s.raw_payload:transactions) f
    where s.client_id = 'client_c'
),

source as (
    select * from client_a_rows
    union all
    select * from client_c_rows
),

parsed as (
    select
        client_id,
        _source_file,
        _loaded_at,
        raw_payload,

        -- ── Transaction ID ─────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'TransactionID'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:id::string), '')
        end as source_transaction_id,

        -- ── Order ID ────────────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'OrderID'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:order:id::string), '')
        end as source_order_id,

        -- ── Customer ID ─────────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'CustomerID'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:order:customer:id::string), '')
        end as source_customer_id,

        -- ── Order Date ──────────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                try_cast(
                    nullif(trim(get_path(xmlget(raw_payload, 'OrderDate'), '$')::string), '')
                    as date
                )
            when 'client_c' then
                try_cast(nullif(raw_payload:order:date::string, '') as date)
        end as order_date,

        -- ── Customer name ───────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'FirstName'), '$')::string), '')
            when 'client_c' then
                split_part(nullif(trim(raw_payload:order:customer:name::string), ''), ' ', 1)
        end as customer_first_name,

        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'LastName'), '$')::string), '')
            when 'client_c' then
                nullif(trim(split_part(nullif(trim(raw_payload:order:customer:name::string), ''), ' ', 2)), '')
        end as customer_last_name,

        -- ── Customer Email ──────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'Email'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:order:customer:email::string), '')
        end as customer_email,

        -- ── Payment ─────────────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'Method'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:payment:method::string), '')
        end as payment_method,

        case client_id
            when 'client_a' then
                try_cast(get_path(xmlget(raw_payload, 'Amount'), '$')::string as number(12, 2))
            when 'client_c' then
                try_cast(raw_payload:payment:total::string as number(12, 2))
        end as payment_amount,

        case client_id
            when 'client_a' then
                upper(nullif(trim(
                    get_path(xmlget(raw_payload, 'Amount'), '@currency')::string
                ), ''))
            when 'client_c' then
                upper(nullif(trim(raw_payload:payment:currency::string), ''))
        end as payment_currency,

        -- ── Has line items ──────────────────────────────────────────────────
        case client_id
            when 'client_a' then
                (xmlget(raw_payload, 'Items') is not null)
            when 'client_c' then
                (array_size(raw_payload:items) > 0)
        end as has_line_items

    from source
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by client_id, source_transaction_id
            order by _loaded_at asc
        ) as _row_num
    from parsed
    where source_transaction_id is not null
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['client_id', 'source_transaction_id']) }}
            as transaction_sk,

        client_id,
        source_transaction_id,
        source_order_id,
        source_customer_id,
        order_date,
        (order_date is null)                                         as order_date_is_missing,
        customer_first_name,
        customer_last_name,
        customer_email,
        {{ validate_email('customer_email') }}                       as customer_email_is_valid,
        payment_method,
        payment_amount,
        (payment_amount is not null and payment_amount > 0)          as payment_amount_is_valid,
        payment_currency,
        has_line_items,

        (_row_num > 1)                                               as _is_duplicate,
        _source_file,
        _loaded_at

    from deduplicated
)

select * from final
