{{ config(unique_key='item_sk') }}

-- =============================================================================
-- mart_transaction_items — Gold layer
-- One clean row per line item, unnested from transaction payloads.
-- Client A items come from XML <Item> nodes; Client C from JSON items[].
--
-- Sourced from stg_transaction_items with:
--   - Null transaction IDs excluded (source_transaction_id IS NOT NULL)
--   - Null SKUs excluded (source_sku IS NOT NULL)
--
-- Note: stg_transaction_items has no _is_duplicate flag — the surrogate key
-- is (client_id, source_transaction_id, source_sku), which is naturally
-- unique per line item.
-- =============================================================================

with

source as (
    select * from {{ ref('stg_transaction_items') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        item_sk,
        client_id,
        source_transaction_id,
        source_sku,
        item_description,
        quantity,
        quantity_is_valid,
        unit_price,
        unit_price_is_valid,
        currency,
        line_total,
        _loaded_at
    from source
    where source_transaction_id is not null
      and source_sku is not null
      and {{ is_clean_id('source_transaction_id', 'transaction_id') }}
      and {{ is_clean_id('source_sku', 'sku') }}
)

select * from final
