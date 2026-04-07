{{ config(unique_key='customer_sk') }}

-- =============================================================================
-- stg_customers — Silver layer
-- One row per unique customer per client, deduplicated, with DQ flags.
--
-- Sources:
--   Client A: Customer.csv  — columns: customer_id, first_name, last_name,
--             email, loyalty_tier, signup_source, is_active
--   Client C: Customer.CSV  — columns: customer_id, customer_name, email,
--             segment, is_active  (no signup_source, no first/last split)
--
-- Anomalies handled:
--   - Duplicates: deduped by (client_id, source_customer_id), keep first loaded
--   - Sentinel last_name "Unknown" → NULL
--   - Sentinel segment "UNKNOWN" → NULL
--   - Invalid emails flagged (not dropped) via validate_email macro
--   - Null-heavy rows retained with all nulled fields and _is_duplicate = false
-- =============================================================================

with

source as (
    select * from {{ source('raw', 'CUSTOMERS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by client_id, customer_id
            order by _loaded_at asc
        ) as _row_num
    from source
),

cleaned as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['client_id', 'customer_id']) }}
            as customer_sk,

        client_id,
        {{ clean_string('customer_id') }}                           as source_customer_id,

        -- Name — Client A has first/last columns; Client C has a single customer_name
        case
            when client_id = 'client_a'
                then {{ clean_string('first_name') }}
            else split_part({{ clean_string('customer_name') }}, ' ', 1)
        end                                                          as first_name,

        case
            when client_id = 'client_a'
                then nullif(trim(last_name), 'Unknown')
            else nullif(trim(split_part({{ clean_string('customer_name') }}, ' ', 2)), '')
        end                                                          as last_name,

        case
            when client_id = 'client_a'
                then concat_ws(
                         ' ',
                         {{ clean_string('first_name') }},
                         nullif(trim(last_name), 'Unknown')
                     )
            else {{ clean_string('customer_name') }}
        end                                                          as full_name,

        -- Email
        {{ clean_string('email') }}                                  as email,
        {{ validate_email(clean_string('email')) }}                  as email_is_valid,

        -- Tier — Client A: loyalty_tier; Client C: segment
        case
            when client_id = 'client_a' then {{ clean_string('loyalty_tier') }}
            else nullif(trim(segment), 'UNKNOWN')
        end                                                          as source_customer_tier,

        -- Canonical tier mapping (BRONZE/SILVER/GOLD/PLATINUM → unified)
        case upper(
            case
                when client_id = 'client_a' then {{ clean_string('loyalty_tier') }}
                else nullif(trim(segment), 'UNKNOWN')
            end
        )
            when 'BRONZE'   then 'BRONZE'
            when 'SILVER'   then 'SILVER'
            when 'GOLD'     then 'GOLD'
            when 'PLATINUM' then 'PLATINUM'
            else null
        end                                                          as canonical_customer_tier,

        -- Client A only — NULL for Client C
        case when client_id = 'client_a'
            then {{ clean_string('signup_source') }}
        end                                                          as signup_source,

        try_cast(is_active as boolean)                               as is_active,

        -- Data quality flags
        (_row_num > 1)                                               as _is_duplicate,
        _source_file,
        _loaded_at

    from deduplicated
)

select * from cleaned
