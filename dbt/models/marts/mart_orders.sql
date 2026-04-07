{{ config(unique_key='order_sk') }}

-- =============================================================================
-- mart_orders — Gold layer
-- One clean row per unique order per client.
--
-- Sourced from stg_orders with:
--   - Duplicates removed (_is_duplicate = false)
--   - Null source IDs excluded (source_order_id IS NOT NULL)
-- =============================================================================

with

source as (
    select * from {{ ref('stg_orders') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        order_sk,
        client_id,
        source_order_id,
        source_customer_id,
        order_date,
        order_date_is_missing,
        order_status,
        channel,
        customer_ref_is_valid,
        _loaded_at
    from source
    where not _is_duplicate
      and source_order_id is not null
)

select * from final
