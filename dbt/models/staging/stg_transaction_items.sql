{{ config(unique_key='item_sk') }}

-- =============================================================================
-- stg_transaction_items — Silver layer
-- One row per line item, unnested from the TRANSACTIONS raw_payload VARIANT.
--
-- Sources:
--   Client A: XML <Items><Item> nodes, unnested via LATERAL FLATTEN on XMLGET
--   Client C: JSON items[] array, unnested via LATERAL FLATTEN
--
-- Anomalies handled:
--   - Negative quantities: flagged with quantity_is_valid = false
--   - Zero quantities: flagged as invalid
--   - Zero / negative unit prices: flagged with unit_price_is_valid = false
--   - Empty SKUs: retained with source_sku = NULL
--   - line_total computed only when both quantity and unit_price are valid
-- =============================================================================

with

raw_source as (
    select * from {{ source('raw', 'TRANSACTIONS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

-- ── Client A: flatten XML <Item> nodes ───────────────────────────────────────
-- Client A rows are already one-per-transaction (STRIP_OUTER_ELEMENT = TRUE).
client_a_items as (
    select
        s.client_id,
        s._source_file,
        s._loaded_at,

        nullif(trim(get_path(xmlget(s.raw_payload, 'TransactionID'), '$')::string), '')
            as source_transaction_id,

        nullif(trim(get_path(xmlget(f.value, 'SKU'), '$')::string), '')
            as source_sku,

        nullif(trim(get_path(xmlget(f.value, 'Description'), '$')::string), '')
            as item_description,

        try_cast(get_path(xmlget(f.value, 'Quantity'), '$')::string as integer)
            as quantity,

        try_cast(get_path(xmlget(f.value, 'UnitPrice'), '$')::string as number(12, 2))
            as unit_price,

        upper(nullif(trim(
            get_path(xmlget(f.value, 'UnitPrice'), '@currency')::string
        ), ''))                                                      as currency

    from raw_source s,
        lateral flatten(input => xmlget(s.raw_payload, 'Items'):$) f
    where s.client_id = 'client_a'
),

-- ── Client C: double-flatten JSON transactions → items ────────────────────────
-- Client C loads one VARIANT row per file (outer doc is an object, not array).
-- First flatten the transactions array, then flatten each transaction's items.
client_c_items as (
    select
        s.client_id,
        s._source_file,
        s._loaded_at,

        nullif(trim(txn.value:id::string), '')
            as source_transaction_id,

        nullif(trim(item.value:sku::string), '')
            as source_sku,

        nullif(trim(item.value:description::string), '')
            as item_description,

        try_cast(item.value:qty::string as integer)
            as quantity,

        try_cast(item.value:price:amount::string as number(12, 2))
            as unit_price,

        upper(nullif(trim(item.value:price:currency::string), ''))
            as currency

    from raw_source s,
        lateral flatten(input => s.raw_payload:transactions) txn,
        lateral flatten(input => txn.value:items) item
    where s.client_id = 'client_c'
      and array_size(s.raw_payload:transactions) > 0
      and array_size(txn.value:items) > 0
),

combined as (
    select * from client_a_items
    union all
    select * from client_c_items
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['client_id', 'source_transaction_id', 'source_sku']) }}
            as item_sk,

        client_id,
        source_transaction_id,
        source_sku,
        item_description,

        quantity,
        (quantity is not null and quantity > 0)                      as quantity_is_valid,

        unit_price,
        {{ is_valid_price('unit_price') }}                           as unit_price_is_valid,

        currency,

        -- line_total only when both quantity and price are valid
        case
            when quantity is not null and quantity > 0
             and unit_price is not null and unit_price > 0
            then (quantity * unit_price)::number(12, 2)
        end                                                          as line_total,

        _source_file,
        _loaded_at

    from combined
    where source_transaction_id is not null
)

select * from final
