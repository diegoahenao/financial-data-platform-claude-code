{{ config(unique_key='product_sk') }}

-- =============================================================================
-- mart_products — Gold layer
-- One clean row per unique SKU per client.
--
-- Sourced from stg_products with:
--   - Duplicates removed (_is_duplicate = false)
--   - Null source IDs excluded (source_sku IS NOT NULL)
-- =============================================================================

with

source as (
    select * from {{ ref('stg_products') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        product_sk,
        client_id,
        source_sku,
        product_name,
        category,
        unit_price,
        unit_price_is_valid,
        currency,
        is_active,
        _loaded_at
    from source
    where not _is_duplicate
      and source_sku is not null
)

select * from final
