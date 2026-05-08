-- Intermediate model: int_layering_detection
-- Detects layering patterns (rapid funds in-out movement with no legitimate purpose)
-- AMLA suspicious indicator per BSP Circular 706 Annex A
-- Purpose: Silver layer - AML detection signal

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['txn_date_ph']},
    ]
) }}

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

-- Pre-compute daily counts to avoid nested aggregate
daily_counts AS (
    SELECT
        customer_id,
        txn_date_ph,
        COUNT(*) AS daily_txn_count
    FROM transactions
    WHERE amount_php > 0
    GROUP BY customer_id, txn_date_ph
),

-- 48-hour observation window
customer_daily_txn AS (
    SELECT
        t.txn_id,
        t.customer_id,
        t.branch_code,
        t.txn_date_ph,
        t.txn_ts_ph,
        t.amount_php,
        t.transaction_direction,
        t.purpose_description,
        SUM(CASE WHEN t.transaction_direction = 'CREDIT' THEN t.amount_php ELSE 0 END) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.txn_date_ph
            RANGE BETWEEN INTERVAL '2 days' PRECEDING AND CURRENT ROW
        ) AS amount_in_48h,
        SUM(CASE WHEN t.transaction_direction = 'DEBIT' THEN t.amount_php ELSE 0 END) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.txn_date_ph
            RANGE BETWEEN INTERVAL '2 days' PRECEDING AND CURRENT ROW
        ) AS amount_out_48h,
        SUM(t.amount_php) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.txn_date_ph
            RANGE BETWEEN INTERVAL '2 days' PRECEDING AND CURRENT ROW
        ) AS net_amount_48h,
        COUNT(*) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.txn_date_ph
            RANGE BETWEEN INTERVAL '2 days' PRECEDING AND CURRENT ROW
        ) AS txn_count_48h,

        -- ✅ AVG over pre-computed daily counts, no nested aggregate
        AVG(dc.daily_txn_count) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.txn_date_ph
            RANGE BETWEEN INTERVAL '90 days' PRECEDING AND CURRENT ROW
        ) AS avg_daily_velocity_90d

    FROM transactions t
    JOIN daily_counts dc
        ON t.customer_id = dc.customer_id
        AND t.txn_date_ph = dc.txn_date_ph
    WHERE t.amount_php > 0
),


-- Detect layering: in-out movement with minimal net position
layering_txns AS (
    SELECT
        txn_id,
        customer_id,
        branch_code,
        txn_date_ph,
        transaction_direction,
        amount_php,
        amount_in_48h,
        amount_out_48h,
        net_amount_48h,
        txn_count_48h,
        avg_daily_velocity_90d,
        purpose_description,
        
        -- Layering pattern: both in and out, low net position
        CASE
            WHEN amount_in_48h > 50000
              AND amount_out_48h > 50000
              AND (net_amount_48h::NUMERIC / NULLIF((amount_in_48h + amount_out_48h), 0)) < 0.10
              THEN TRUE
            ELSE FALSE
        END AS is_layering_pattern,
        
        -- Velocity anomaly: transactions spike above normal customer behavior
        CASE
            WHEN txn_count_48h > (COALESCE(avg_daily_velocity_90d, 1) * 2)
              AND amount_in_48h > 0
              AND amount_out_48h > 0
              THEN TRUE
            ELSE FALSE
        END AS velocity_anomaly
    FROM customer_daily_txn
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'txn_date_ph']) }} AS layering_event_id,
    txn_id,
    customer_id,
    branch_code,
    txn_date_ph,
    transaction_direction,
    amount_php,
    amount_in_48h,
    amount_out_48h,
    net_amount_48h,
    ROUND(((net_amount_48h::NUMERIC / NULLIF((amount_in_48h + amount_out_48h), 0)) * 100), 2) AS net_position_pct,
    txn_count_48h,
    ROUND(avg_daily_velocity_90d, 2) AS avg_daily_velocity_90d,
    
    is_layering_pattern,
    velocity_anomaly,
    
    CASE
        WHEN is_layering_pattern THEN 'LAYER_01'
        ELSE NULL
    END AS str_indicator_code,
    
    CASE
        WHEN is_layering_pattern THEN 65
        ELSE 0
    END AS risk_score_layering,
    
    purpose_description,
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at

FROM layering_txns

WHERE is_layering_pattern = TRUE
   OR velocity_anomaly = TRUE
