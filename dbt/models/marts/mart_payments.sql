{{ config(unique_key='payment_sk') }}

-- =============================================================================
-- mart_payments — Gold layer
-- One clean row per unique payment event per client.
-- Unified from three sources: standalone payments CSV, XML transaction
-- payments, and JSON transaction payments.
--
-- Sourced from stg_payments with:
--   - Duplicates removed (_is_duplicate = false)
--   - Null source IDs excluded (source_payment_id IS NOT NULL)
-- =============================================================================

with

source as (
    select * from {{ ref('stg_payments') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        payment_sk,
        client_id,
        source_payment_id,
        source_order_id,
        payment_method,
        status,
        amount,
        amount_is_valid,
        is_refund,
        currency,
        processing_fee,
        source_type,
        _loaded_at
    from source
    where not _is_duplicate
      and source_payment_id is not null
      and {{ is_clean_id('source_payment_id', 'payment_id') }}
)

select * from final
