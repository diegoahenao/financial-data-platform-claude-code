{{ config(unique_key='transaction_sk') }}

-- =============================================================================
-- mart_transactions — Gold layer
-- One clean row per unique transaction per client.
-- Parsed from raw XML (Client A) and JSON (Client C) payloads via Silver.
--
-- Sourced from stg_transactions with:
--   - Duplicates removed (_is_duplicate = false)
--   - Null source IDs excluded (source_transaction_id IS NOT NULL)
-- =============================================================================

with

source as (
    select * from {{ ref('stg_transactions') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        transaction_sk,
        client_id,
        source_transaction_id,
        source_order_id,
        source_customer_id,
        order_date,
        order_date_is_missing,
        customer_first_name,
        customer_last_name,
        customer_email,
        customer_email_is_valid,
        payment_method,
        payment_amount,
        payment_amount_is_valid,
        payment_currency,
        has_line_items,
        _loaded_at
    from source
    where not _is_duplicate
      and source_transaction_id is not null
)

select * from final
