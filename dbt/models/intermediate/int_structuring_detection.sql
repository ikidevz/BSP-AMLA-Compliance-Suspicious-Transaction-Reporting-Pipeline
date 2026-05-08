-- Intermediate model: int_structuring_detection
-- Detects cash structuring patterns (breaking up large transactions to avoid CTR)
-- AMLA suspicious indicator per BSP Circular 706 Annex A
-- Purpose: Silver layer - AML detection signal

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['observation_window_start_date']},
    ]
) }}

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

-- 7-day rolling window cash transactions
txn_window_7d AS (
    SELECT
        t1.txn_id,
        t1.customer_id,
        t1.branch_code,
        t1.txn_date_ph,
        t1.amount_php,
        t1.txn_type,
        COUNT(*) OVER (
            PARTITION BY t1.customer_id
            ORDER BY t1.txn_date_ph
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ) AS txn_count_7d,
        SUM(t1.amount_php) OVER (
            PARTITION BY t1.customer_id
            ORDER BY t1.txn_date_ph
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ) AS txn_sum_7d,
        MIN(t1.txn_date_ph) OVER (
            PARTITION BY t1.customer_id
            ORDER BY t1.txn_date_ph
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ) AS observation_window_start_date
    FROM transactions t1
    WHERE t1.txn_type = 'CASH'
      AND t1.amount_php > 0
      AND t1.transaction_direction = 'DEBIT'  -- Withdrawals are typical structuring pattern
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'txn_date_ph', 'observation_window_start_date']) }} AS structuring_event_id,
    txn_id,
    customer_id,
    branch_code,
    txn_date_ph,
    observation_window_start_date,
    amount_php,
    txn_count_7d,
    txn_sum_7d,
    
    -- Structuring indicators per BSP Circular 706 Annex A:
    -- Multiple sub-threshold transactions in short period
    CASE
        WHEN txn_count_7d >= 3
          AND txn_sum_7d >= 450000
          AND amount_php < 490000
          THEN TRUE
        ELSE FALSE
    END AS is_structuring_pattern,
    
    CASE
        WHEN txn_count_7d >= 3
          AND txn_sum_7d >= 450000
          AND amount_php < 490000
          THEN 'STRUCT_01'
        ELSE NULL
    END AS str_indicator_code,
    
    CASE
        WHEN txn_count_7d >= 3
          AND txn_sum_7d >= 450000
          AND amount_php < 490000
          THEN 70  -- Base risk score from seeds.str_indicators_ref
        ELSE 0
    END AS risk_score_structuring,
    
    -- Pattern details
    ROUND(((txn_sum_7d - 500000)::NUMERIC / 500000 * 100), 2) AS threshold_evasion_pct,
    
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at

FROM txn_window_7d

WHERE txn_count_7d >= 3
  AND txn_sum_7d >= 450000
