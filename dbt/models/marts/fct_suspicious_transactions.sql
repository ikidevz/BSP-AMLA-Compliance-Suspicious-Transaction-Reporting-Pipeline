-- models/marts/fct_suspicious_transactions.sql
-- Fact Table: fct_suspicious_transactions
-- Suspicious Transaction Report (STR) candidates per RA 9160 Sec 3(b-1)
-- No amount threshold; 5 Philippine working day filing deadline

{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_fct_str_customer       ON {{ this }}(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_fct_str_determination  ON {{ this }}(str_determination_ts DESC)",
        "CREATE INDEX IF NOT EXISTS idx_fct_str_deadline       ON {{ this }}(str_filing_deadline)",
        "CREATE INDEX IF NOT EXISTS idx_fct_str_filing_status  ON {{ this }}(filing_status) WHERE filing_status IN ('PENDING', 'OVERDUE')",
        "CREATE INDEX IF NOT EXISTS idx_fct_str_urgency        ON {{ this }}(filing_urgency) WHERE filing_urgency IN ('OVERDUE', 'DUE_SOON')",
        "CREATE INDEX IF NOT EXISTS idx_fct_str_risk_score     ON {{ this }}(max_risk_score DESC) WHERE max_risk_score >= 75"
    ]
) }}

WITH str_candidates AS (
    SELECT * FROM {{ ref('int_str_candidates') }}
),

transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

str_indicators AS (
    SELECT * FROM {{ source('seeds', 'str_indicators_ref') }}
),

-- Pre-compute the 5-PH-working-day deadline once per candidate
-- using the macro — eliminates the 5× duplication from the original
deadlines AS (
    SELECT
        str_candidate_id,
        str_determination_ts,
        {{ ph_working_day_deadline('str_determination_ts::DATE', 5) }}::DATE
            AS str_filing_deadline
    FROM str_candidates
),

-- Aggregate indicator risk scores per candidate
indicator_scores AS (
    SELECT
        sc.str_candidate_id,
        SUM(CASE WHEN si.indicator_category = 'STRUCTURING'  THEN si.base_risk_score ELSE 0 END) AS structuring_risk,
        SUM(CASE WHEN si.indicator_category = 'LAYERING'     THEN si.base_risk_score ELSE 0 END) AS layering_risk,
        SUM(CASE WHEN si.indicator_category = 'JURISDICTION' THEN si.base_risk_score ELSE 0 END) AS jurisdiction_risk,
        SUM(CASE WHEN si.indicator_category = 'PEP'          THEN si.base_risk_score ELSE 0 END) AS pep_risk
    FROM str_candidates sc
    JOIN str_indicators si
        ON si.indicator_code = ANY(sc.str_indicators)
    GROUP BY sc.str_candidate_id
),

str_enriched AS (
    SELECT
        sc.str_candidate_id                             AS str_id,
        sc.txn_id,
        sc.customer_id,
        sc.branch_code,
        sc.txn_date_ph,
        sc.str_indicators,
        sc.indicator_count,
        sc.max_risk_score,

        t.amount_php                                    AS transaction_amount_php,

        -- Risk breakdown by category
        COALESCE(iscr.structuring_risk,  0)             AS structuring_risk,
        COALESCE(iscr.layering_risk,     0)             AS layering_risk,
        COALESCE(iscr.jurisdiction_risk, 0)             AS jurisdiction_risk,
        COALESCE(iscr.pep_risk,          0)             AS pep_risk,

        -- STR timeline (macro replaces the 5× CTE duplication)
        sc.str_determination_ts,
        dl.str_filing_deadline,

        -- Days remaining to deadline (negative = overdue)
        dl.str_filing_deadline - CURRENT_DATE           AS days_to_deadline,

        -- Filing urgency derived from single deadline expression
        CASE
            WHEN dl.str_filing_deadline - CURRENT_DATE <= 0 THEN 'OVERDUE'
            WHEN dl.str_filing_deadline - CURRENT_DATE <= 2 THEN 'DUE_SOON'
            ELSE 'PENDING'
        END                                             AS filing_urgency,

        'PENDING'::VARCHAR                              AS filing_status,
        NULL::DATE                                      AS filed_at,
        NULL::VARCHAR                                   AS amlc_ers_reference,

        sc.str_confidence_level,
        sc.signal_details,

        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'   AS dbt_loaded_at

    FROM str_candidates sc
    LEFT JOIN transactions t
        ON sc.txn_id = t.txn_id
    LEFT JOIN deadlines dl
        ON sc.str_candidate_id = dl.str_candidate_id
    LEFT JOIN indicator_scores iscr
        ON sc.str_candidate_id = iscr.str_candidate_id
)

SELECT * FROM str_enriched