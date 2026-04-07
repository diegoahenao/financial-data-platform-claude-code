{{ config(unique_key='customer_sk') }}

-- =============================================================================
-- mart_customers — Gold layer
-- One clean row per unique customer per client.
--
-- Sourced from stg_customers with:
--   - Duplicates removed (_is_duplicate = false)
--   - Null source IDs excluded (source_customer_id IS NOT NULL)
--
-- Audit columns (_is_duplicate, _source_file) are dropped.
-- =============================================================================

with

source as (
    select * from {{ ref('stg_customers') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

final as (
    select
        customer_sk,
        client_id,
        source_customer_id,
        first_name,
        last_name,
        full_name,
        email,
        email_is_valid,
        source_customer_tier,
        canonical_customer_tier,
        signup_source,
        is_active,
        _loaded_at
    from source
    where not _is_duplicate
      and source_customer_id is not null
      and {{ is_clean_id('source_customer_id', 'customer_id') }}
)

select * from final
