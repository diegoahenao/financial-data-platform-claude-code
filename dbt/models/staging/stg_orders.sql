{{ config(unique_key='order_sk') }}

-- =============================================================================
-- stg_orders — Silver layer
-- One row per unique order per client, with DQ flags.
--
-- Sources:
--   Client A: Orders.csv   — columns: order_id, customer_id, order_date,
--             order_status, channel
--   Client C: Order.csv    — columns: order_id, customer_id, order_date,
--             order_status  (no channel column)
--
-- Anomalies handled:
--   - Duplicates: deduped by (client_id, source_order_id)
--   - Missing order_date: retained with order_date_is_missing = true
--   - Referential integrity flag for unknown customer_ids (not dropped)
-- =============================================================================

with

source as (
    select * from {{ source('raw', 'ORDERS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by client_id, order_id
            order by _loaded_at asc
        ) as _row_num
    from source
),

valid_customers as (
    select distinct client_id, source_customer_id
    from {{ ref('stg_customers') }}
    where not _is_duplicate
),

cleaned as (
    select
        {{ dbt_utils.generate_surrogate_key(['d.client_id', 'd.order_id']) }}
            as order_sk,

        d.client_id,
        {{ clean_string('d.order_id') }}                             as source_order_id,
        {{ clean_string('d.customer_id') }}                          as source_customer_id,

        try_cast({{ clean_string('d.order_date') }} as date)         as order_date,
        ({{ clean_string('d.order_date') }} is null)                 as order_date_is_missing,

        {{ clean_string('d.order_status') }}                         as order_status,

        -- Client A only
        case when d.client_id = 'client_a'
            then {{ clean_string('d.channel') }}
        end                                                          as channel,

        -- Referential integrity flag
        (vc.source_customer_id is not null)                          as customer_ref_is_valid,

        (_row_num > 1)                                               as _is_duplicate,
        d._source_file,
        d._loaded_at

    from deduplicated d
    left join valid_customers vc
        on d.client_id = vc.client_id
        and {{ clean_string('d.customer_id') }} = vc.source_customer_id
)

select * from cleaned
