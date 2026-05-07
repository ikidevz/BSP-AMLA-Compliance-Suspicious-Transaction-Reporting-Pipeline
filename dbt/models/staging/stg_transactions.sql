-- Staging model: stg_transactions
-- Validate and cast raw transactions from staging.raw_transactions
-- Purpose: Bronze layer normalization for downstream AML processing

{{ config(
    materialized='table',
    schema='bronze',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['txn_date_ph']},
        {'columns': ['txn_type']},
    ]
) }}

WITH raw_txn AS (
    SELECT
        txn_id,
        customer_id,
        branch_code,
        txn_date_ph,
        txn_time_ph,
        txn_type,
        txn_channel,
        transaction_direction,
        amount_local,
        currency_code,
        amount_php,
        counterparty_name,
        counterparty_account,
        counterparty_bank,
        purpose_code,
        purpose_description,
        reference_number,
        source_system,
        batch_id,
        created_at,
        updated_at
    FROM {{ source('staging', 'raw_transactions') }}
)

SELECT
    -- Primary key
    raw_txn.txn_id,
    
    -- Fact dimensions
    raw_txn.customer_id,
    raw_txn.branch_code,
    
    -- Dates and times (normalized to PHT)
    raw_txn.txn_date_ph::DATE AS txn_date_ph,
    raw_txn.txn_time_ph::TIME AS txn_time_ph,
    (raw_txn.txn_date_ph::DATE || ' ' || raw_txn.txn_time_ph::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Manila' AS txn_ts_ph,
    
    -- Transaction attributes (cast to correct types)
    UPPER(TRIM(raw_txn.txn_type))::VARCHAR AS txn_type,
    UPPER(TRIM(raw_txn.txn_channel))::VARCHAR AS txn_channel,
    UPPER(TRIM(raw_txn.transaction_direction))::VARCHAR AS transaction_direction,
    
    -- Amounts (cast to numeric, validate)
    CAST(raw_txn.amount_local AS NUMERIC(19, 4)) AS amount_local,
    UPPER(TRIM(raw_txn.currency_code))::CHAR(3) AS currency_code,
    CAST(raw_txn.amount_php AS NUMERIC(19, 2)) AS amount_php,
    
    -- Counterparty (full PII - will be masked at Silver layer)
    TRIM(raw_txn.counterparty_name)::VARCHAR AS counterparty_name,
    TRIM(raw_txn.counterparty_account)::VARCHAR AS counterparty_account,
    TRIM(raw_txn.counterparty_bank)::VARCHAR AS counterparty_bank,
    
    -- Transaction narrative
    TRIM(raw_txn.purpose_code)::VARCHAR AS purpose_code,
    TRIM(raw_txn.purpose_description)::VARCHAR AS purpose_description,
    
    -- Identifiers
    TRIM(raw_txn.reference_number)::VARCHAR AS reference_number,
    TRIM(raw_txn.source_system)::VARCHAR AS source_system,
    raw_txn.batch_id,
    
    -- Audit columns
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at
    
FROM raw_txn

-- Data quality: Remove null customer or amounts
WHERE raw_txn.customer_id IS NOT NULL
  AND raw_txn.amount_php > 0
  AND raw_txn.txn_date_ph IS NOT NULL
