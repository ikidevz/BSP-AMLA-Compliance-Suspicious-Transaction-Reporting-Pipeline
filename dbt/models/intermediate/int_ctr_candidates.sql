-- Intermediate model: int_ctr_candidates
-- Identifies Covered Transaction Report (CTR) eligible transactions
-- BSP Circular 706: PHP 500,000 cash threshold
-- Purpose: Silver layer - AML detection signal

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['txn_date_ph']},
        {'columns': ['ctr_type']},
    ]
) }}

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

-- Single transaction CTR: one transaction >= PHP 500,000 cash
single_ctr AS (
    SELECT
        txn_id,
        customer_id,
        branch_code,
        txn_date_ph,
        txn_type,
        txn_channel,
        amount_php,
        counterparty_name,
        counterparty_account,
        'SINGLE_CASH' AS ctr_type,
        amount_php AS ctr_amount_php,
        transaction_direction,
        TRUE AS is_ctr_candidate
    FROM transactions
    WHERE txn_type = 'CASH'
      AND amount_php >= {{ var('ctr_php_threshold', 500000) }}
),

-- Related transactions CTR: same customer, same banking day, combined amount >= PHP 500,000
related_txns_daily AS (
    SELECT
        t1.txn_id,
        t1.customer_id,
        t1.branch_code,
        t1.txn_date_ph,
        t1.txn_type,
        t1.txn_channel,
        t1.amount_php,
        t1.counterparty_name,
        t1.counterparty_account,
        t1.transaction_direction,
        SUM(t2.amount_php) OVER (
            PARTITION BY t1.customer_id, t1.txn_date_ph
            ORDER BY t1.txn_id
        ) AS daily_sum_php,
        ROW_NUMBER() OVER (
            PARTITION BY t1.customer_id, t1.txn_date_ph
            ORDER BY t1.txn_id
        ) AS txn_rank_by_day
    FROM transactions t1
    JOIN transactions t2
        ON t1.customer_id = t2.customer_id
        AND t1.txn_date_ph = t2.txn_date_ph
        AND t1.txn_type = 'CASH'
    WHERE t2.txn_type = 'CASH'
      AND t2.amount_php > 0
),

related_ctr AS (
    SELECT
        txn_id,
        customer_id,
        branch_code,
        txn_date_ph,
        txn_type,
        txn_channel,
        amount_php,
        counterparty_name,
        counterparty_account,
        'RELATED_CASH' AS ctr_type,
        daily_sum_php AS ctr_amount_php,
        transaction_direction,
        TRUE AS is_ctr_candidate
    FROM related_txns_daily
    WHERE daily_sum_php >= {{ var('ctr_php_threshold', 500000) }}
      AND txn_rank_by_day = 1  -- Report once per customer per day
),

-- FOREX CTR: USD 10,000 equivalent
forex_ctr AS (
    SELECT
        txn_id,
        customer_id,
        branch_code,
        txn_date_ph,
        txn_type,
        txn_channel,
        amount_php,
        counterparty_name,
        counterparty_account,
        'FOREX_EQUIVALENT' AS ctr_type,
        amount_php AS ctr_amount_php,
        transaction_direction,
        TRUE AS is_ctr_candidate
    FROM transactions
    WHERE currency_code NOT IN ('PHP')
      AND amount_php >= ({{ var('ctr_forex_threshold', 10000) }} * 56)  -- Approx PHP 560k at 56:1 rate
      AND txn_type IN ('WIRE', 'SWIFT', 'RTGS')
),

-- Union all CTR candidates
all_ctr AS (
    SELECT * FROM single_ctr
    UNION ALL
    SELECT * FROM related_ctr
    UNION ALL
    SELECT * FROM forex_ctr
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['txn_id', 'ctr_type']) }} AS ctr_candidate_id,
    txn_id,
    customer_id,
    branch_code,
    txn_date_ph,
    txn_type,
    txn_channel,
    amount_php,
    counterparty_name,
    counterparty_account,
    ctr_type,
    ctr_amount_php,
    transaction_direction,
    is_ctr_candidate,
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at
FROM all_ctr
ORDER BY txn_date_ph DESC, txn_id
