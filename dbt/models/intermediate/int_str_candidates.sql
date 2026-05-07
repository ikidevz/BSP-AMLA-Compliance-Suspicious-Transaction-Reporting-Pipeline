-- Intermediate model: int_str_candidates
-- Aggregates all STR indicator signals into one comprehensive candidate table
-- RA 9160 Sec 3(b-1) - Suspicious Transaction Report (no amount threshold)
-- Purpose: Silver layer - STR determination with filing deadlines

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['str_determination_ts']},
        {'columns': ['str_filing_deadline']},
    ]
) }}

WITH structuring_signals AS (
    SELECT
        customer_id,
        txn_id,
        branch_code,
        txn_date_ph,
        'STRUCT_01' AS indicator_code,
        risk_score_structuring AS signal_risk_score,
        txn_count_7d,
        CAST(NULL AS VARCHAR) AS signal_detail
    FROM {{ ref('int_structuring_detection') }}
    WHERE is_structuring_pattern = TRUE
),

layering_signals AS (
    SELECT
        customer_id,
        txn_id,
        branch_code,
        txn_date_ph,
        'LAYER_01' AS indicator_code,
        risk_score_layering AS signal_risk_score,
        CAST(NULL AS INT) AS txn_count_7d,
        CAST(net_position_pct AS VARCHAR) AS signal_detail
    FROM {{ ref('int_layering_detection') }}
    WHERE is_layering_pattern = TRUE
),

-- FATF jurisdiction signals
fatf_signals AS (
    SELECT
        t.customer_id,
        t.txn_id,
        t.branch_code,
        t.txn_date_ph,
        CASE
            WHEN fj.fatf_list_type = 'BLACKLIST' THEN 'JURIS_01'
            ELSE 'JURIS_02'
        END AS indicator_code,
        CASE
            WHEN fj.fatf_list_type = 'BLACKLIST' THEN 90
            ELSE 50
        END AS signal_risk_score,
        CAST(NULL AS INT) AS txn_count_7d,
        fj.country_name AS signal_detail
    FROM {{ ref('stg_transactions') }} t
    JOIN {{ ref('stg_customers') }} c
        ON t.customer_id = c.customer_id
    LEFT JOIN {{ source('seeds', 'fatf_jurisdictions') }} fj
        ON UPPER(t.counterparty_bank) LIKE '%' || fj.iso2_code || '%'
        OR UPPER(t.purpose_description) LIKE '%' || fj.country_name || '%'
    WHERE fj.iso2_code IS NOT NULL
),

-- PEP signals
pep_signals AS (
    SELECT
        t.customer_id,
        t.txn_id,
        t.branch_code,
        t.txn_date_ph,
        'PEP_01' AS indicator_code,
        75 AS signal_risk_score,
        CAST(NULL AS INT) AS txn_count_7d,
        CAST(t.amount_php AS VARCHAR) AS signal_detail
    FROM {{ ref('stg_transactions') }} t
    JOIN {{ ref('stg_customers') }} c
        ON t.customer_id = c.customer_id
    WHERE c.is_pep = TRUE
      AND t.amount_php >= 50000
),

-- Round-number transaction signals (possible smurfing)
round_number_signals AS (
    SELECT
        customer_id,
        txn_id,
        branch_code,
        txn_date_ph,
        'ROUND_01' AS indicator_code,
        30 AS signal_risk_score,
        CAST(NULL AS INT) AS txn_count_7d,
        CAST(amount_php AS VARCHAR) AS signal_detail
    FROM {{ ref('stg_transactions') }}
    WHERE amount_php IN (500000, 1000000, 5000000, 100000, 50000)
      AND txn_type = 'CASH'
),

-- Aggregate all signals
all_signals AS (
    SELECT * FROM structuring_signals
    UNION ALL
    SELECT * FROM layering_signals
    UNION ALL
    SELECT * FROM fatf_signals
    UNION ALL
    SELECT * FROM pep_signals
    UNION ALL
    SELECT * FROM round_number_signals
),

-- Dedup and aggregate by customer-transaction
signal_aggregation AS (
    SELECT
        customer_id,
        txn_id,
        branch_code,
        txn_date_ph,
        ARRAY_AGG(DISTINCT indicator_code) FILTER (WHERE indicator_code IS NOT NULL) AS str_indicators,
        COUNT(DISTINCT indicator_code) AS indicator_count,
        MAX(signal_risk_score) AS max_risk_score,
        STRING_AGG(DISTINCT signal_detail, '; ') FILTER (WHERE signal_detail IS NOT NULL) AS signal_details,
        CURRENT_TIMESTAMP AS str_determination_ts
    FROM all_signals
    GROUP BY customer_id, txn_id, branch_code, txn_date_ph
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'txn_id']) }} AS str_candidate_id,
    txn_id,
    customer_id,
    branch_code,
    txn_date_ph,
    str_indicators,
    indicator_count,
    max_risk_score,
    signal_details,
    str_determination_ts,
    
    -- STR Filing deadline per RA 9160: 5 Philippine working days from determination
    -- Will be calculated using dbt macro in downstream mart model
    str_determination_ts AS str_determination_date,
    
    CASE
        WHEN indicator_count >= 3 THEN 'HIGH'
        WHEN indicator_count >= 2 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS str_confidence_level,
    
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at

FROM signal_aggregation

ORDER BY str_determination_ts DESC, txn_id
