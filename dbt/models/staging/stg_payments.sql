{{ config(unique_key='payment_sk') }}

-- =============================================================================
-- stg_payments — Silver layer
-- One row per payment event, unified from two source types:
--   1. Client C: RAW.PAYMENTS standalone CSV  (source_type = 'payments_csv')
--   2. Client A: payment embedded in RAW.TRANSACTIONS XML (source_type = 'transaction_xml')
--   3. Client C: payment embedded in RAW.TRANSACTIONS JSON (source_type = 'transaction_json')
--
-- Anomalies handled:
--   - Negative amounts: retained, flagged with amount_is_valid = false,
--     is_refund = true (negative OR status = REFUNDED)
--   - Zero amounts: flagged with amount_is_valid = false
--   - Duplicates: deduped by (client_id, source_payment_id)
-- =============================================================================

with

-- ── Source 1: Client C standalone payments CSV ───────────────────────────────
payments_csv as (
    select
        client_id,
        payment_id                                                    as source_payment_id,
        order_id                                                      as source_order_id,
        {{ clean_string('payment_method') }}                          as payment_method,
        {{ clean_string('status') }}                                  as status,
        try_cast(amount as number(12, 2))                             as amount,
        upper({{ clean_string('currency') }})                         as currency,
        null::number(12, 2)                                           as processing_fee,
        'payments_csv'                                                as source_type,
        _source_file,
        _loaded_at
    from {{ source('raw', 'PAYMENTS') }}
    {% if is_incremental() %}
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

-- ── Source 2 & 3: payments embedded in transactions ──────────────────────────
txn_payments as (
    select
        client_id,

        -- Use transaction ID as payment ID for embedded payments
        case client_id
            when 'client_a' then
                concat('PAY-XML-',
                    nullif(trim(get_path(xmlget(raw_payload, 'TransactionID'), '$')::string), ''))
            when 'client_c' then
                concat('PAY-JSON-', nullif(trim(raw_payload:id::string), ''))
        end                                                           as source_payment_id,

        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'OrderID'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:order:id::string), '')
        end                                                           as source_order_id,

        case client_id
            when 'client_a' then
                nullif(trim(get_path(xmlget(raw_payload, 'Method'), '$')::string), '')
            when 'client_c' then
                nullif(trim(raw_payload:payment:method::string), '')
        end                                                           as payment_method,

        null::varchar                                                  as status,

        case client_id
            when 'client_a' then
                try_cast(get_path(xmlget(raw_payload, 'Amount'), '$')::string as number(12, 2))
            when 'client_c' then
                try_cast(raw_payload:payment:total::string as number(12, 2))
        end                                                           as amount,

        case client_id
            when 'client_a' then
                upper(nullif(trim(
                    get_path(xmlget(raw_payload, 'Amount'), '@currency')::string
                ), ''))
            when 'client_c' then
                upper(nullif(trim(raw_payload:payment:currency::string), ''))
        end                                                           as currency,

        -- Client A XML has processing_fee; Client C JSON does not
        case client_id
            when 'client_a' then
                try_cast(
                    get_path(xmlget(raw_payload, 'ProcessingFee'), '$')::string
                    as number(12, 2)
                )
        end                                                           as processing_fee,

        case client_id
            when 'client_a' then 'transaction_xml'
            when 'client_c' then 'transaction_json'
        end                                                           as source_type,

        _source_file,
        _loaded_at

    from {{ source('raw', 'TRANSACTIONS') }}
    where true
    {% if is_incremental() %}
      and _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
      and nullif(trim(
            case client_id
                when 'client_a' then
                    get_path(xmlget(raw_payload, 'TransactionID'), '$')::string
                when 'client_c' then raw_payload:id::string
            end
          ), '') is not null
),

combined as (
    select * from payments_csv
    union all
    select * from txn_payments
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by client_id, source_payment_id
            order by _loaded_at asc
        ) as _row_num
    from combined
    where source_payment_id is not null
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['client_id', 'source_payment_id']) }}
            as payment_sk,

        client_id,
        source_payment_id,
        source_order_id,
        payment_method,
        status,
        amount,
        (amount is not null and amount > 0)                          as amount_is_valid,
        (amount < 0 or upper(status) = 'REFUNDED')                   as is_refund,
        currency,
        processing_fee,
        source_type,

        (_row_num > 1)                                               as _is_duplicate,
        _source_file,
        _loaded_at

    from deduplicated
)

select * from final
