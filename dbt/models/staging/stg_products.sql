{{ config(unique_key='product_sk') }}

-- =============================================================================
-- stg_products — Silver layer
-- One row per unique SKU per client, with DQ flags.
--
-- Sources:
--   Client A: Products.csv — columns: sku, product_name, category,
--             unit_price, currency, is_active
--   Client C: Product.csv  — same column structure
--
-- Anomalies handled:
--   - Duplicates: deduped by (client_id, source_sku)
--   - Negative prices: flagged with unit_price_is_valid = false (not dropped)
--   - Zero prices: flagged as invalid
--   - Sentinel row "Unknown Product" with price=0: retained, flagged
-- =============================================================================

with

source as (
    select * from {{ source('raw', 'PRODUCTS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by client_id, sku
            order by _loaded_at asc
        ) as _row_num
    from source
),

cleaned as (
    select
        {{ dbt_utils.generate_surrogate_key(['client_id', 'sku']) }}
            as product_sk,

        client_id,
        {{ clean_string('sku') }}                                    as source_sku,
        {{ clean_string('product_name') }}                           as product_name,
        {{ clean_string('category') }}                               as category,

        try_cast(unit_price as number(12, 2))                        as unit_price,
        {{ is_valid_price('try_cast(unit_price as number(12,2))') }} as unit_price_is_valid,

        upper({{ clean_string('currency') }})                        as currency,
        try_cast(is_active as boolean)                               as is_active,

        (_row_num > 1)                                               as _is_duplicate,
        _source_file,
        _loaded_at

    from deduplicated
)

select * from cleaned
where {{ is_clean_id('source_sku', 'sku') }}
