-- models/marts/fct_branch_compliance_summary.sql
-- Fact Table: fct_branch_compliance_summary
-- Branch-level AML compliance aggregation — one row per branch
-- Used by Dashboard Page 5 (Branch & Regional Compliance Performance)

{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_fct_branch_summary_branch   ON {{ this }}(branch_code)",
        "CREATE INDEX IF NOT EXISTS idx_fct_branch_summary_region   ON {{ this }}(region_name)",
        "CREATE INDEX IF NOT EXISTS idx_fct_branch_summary_overdue  ON {{ this }}(overdue_strs DESC)",
        "CREATE INDEX IF NOT EXISTS idx_fct_branch_summary_loaded   ON {{ this }}(dbt_loaded_at DESC)"
    ]
) }}

-- Pre-aggregate customer compliance per branch FIRST before any joins
WITH branch_customer_agg AS (
    SELECT
        branch_code,
        COUNT(DISTINCT customer_id)                                         AS unique_customers,
        SUM(CASE WHEN kyc_exception = TRUE  THEN 1 ELSE 0 END)             AS kyc_exceptions,
        SUM(CASE WHEN risk_tier = 'HIGH'    THEN 1 ELSE 0 END)             AS high_risk_customers,
        SUM(CASE WHEN risk_tier = 'MEDIUM'  THEN 1 ELSE 0 END)             AS medium_risk_customers,
        SUM(CASE WHEN risk_tier = 'LOW'     THEN 1 ELSE 0 END)             AS low_risk_customers,
        SUM(CASE WHEN is_pep = TRUE         THEN 1 ELSE 0 END)             AS pep_customers,
        SUM(CASE WHEN kyc_freshness_flag = TRUE THEN 1 ELSE 0 END)         AS stale_kyc_customers,
        ROUND(AVG(overall_risk_score), 2)                                   AS avg_risk_score
    FROM {{ ref('fct_customer_compliance') }}
    GROUP BY branch_code
),

-- Pre-aggregate CTR facts per branch
branch_ctr_agg AS (
    SELECT
        branch_code,
        COUNT(*)                                                             AS ctr_count,
        SUM(amount_php)                                                      AS ctr_value_php,
        COUNT(CASE WHEN transaction_direction = 'CREDIT' THEN 1 END)        AS ctr_inbound_count,
        COUNT(CASE WHEN transaction_direction = 'DEBIT'  THEN 1 END)        AS ctr_outbound_count,
        MAX(amount_php)                                                      AS ctr_max_amount_php,
        ROUND(AVG(amount_php), 2)                                            AS ctr_avg_amount_php,
        COUNT(CASE WHEN filing_status = 'PENDING' THEN 1 END)               AS ctr_pending_count
    FROM {{ ref('fct_covered_transactions') }}
    GROUP BY branch_code
),

-- Pre-aggregate STR facts per branch
branch_str_agg AS (
    SELECT
        branch_code,
        COUNT(*)                                                             AS str_count,
        SUM(CASE WHEN filing_urgency = 'OVERDUE'   THEN 1 ELSE 0 END)      AS overdue_strs,
        SUM(CASE WHEN filing_urgency = 'DUE_SOON'  THEN 1 ELSE 0 END)      AS due_soon_strs,
        SUM(CASE WHEN filing_urgency = 'PENDING'   THEN 1 ELSE 0 END)      AS pending_strs,
        ROUND(AVG(max_risk_score), 2)                                        AS avg_str_risk_score,
        MAX(max_risk_score)                                                  AS max_str_risk_score,
        COUNT(CASE WHEN str_confidence_level = 'HIGH'   THEN 1 END)         AS high_confidence_strs,
        COUNT(CASE WHEN str_confidence_level = 'MEDIUM' THEN 1 END)         AS medium_confidence_strs
    FROM {{ ref('fct_suspicious_transactions') }}
    GROUP BY branch_code
)

SELECT
    b.branch_code,
    b.branch_name,
    b.region_name,
    b.city_municipality,
    b.province,

    -- Customer metrics
    COALESCE(cc.unique_customers,       0)      AS unique_customers,
    COALESCE(cc.high_risk_customers,    0)      AS high_risk_customers,
    COALESCE(cc.medium_risk_customers,  0)      AS medium_risk_customers,
    COALESCE(cc.low_risk_customers,     0)      AS low_risk_customers,
    COALESCE(cc.pep_customers,          0)      AS pep_customers,
    COALESCE(cc.kyc_exceptions,         0)      AS kyc_exceptions,
    COALESCE(cc.stale_kyc_customers,    0)      AS stale_kyc_customers,
    COALESCE(cc.avg_risk_score,         0)      AS avg_customer_risk_score,

    -- CTR metrics
    COALESCE(ctr.ctr_count,             0)      AS ctr_count,
    COALESCE(ctr.ctr_value_php,         0)      AS ctr_value_php,
    COALESCE(ctr.ctr_inbound_count,     0)      AS ctr_inbound_count,
    COALESCE(ctr.ctr_outbound_count,    0)      AS ctr_outbound_count,
    COALESCE(ctr.ctr_max_amount_php,    0)      AS ctr_max_amount_php,
    COALESCE(ctr.ctr_avg_amount_php,    0)      AS ctr_avg_amount_php,
    COALESCE(ctr.ctr_pending_count,     0)      AS ctr_pending_count,

    -- STR metrics
    COALESCE(str.str_count,             0)      AS str_count,
    COALESCE(str.overdue_strs,          0)      AS overdue_strs,
    COALESCE(str.due_soon_strs,         0)      AS due_soon_strs,
    COALESCE(str.pending_strs,          0)      AS pending_strs,
    COALESCE(str.avg_str_risk_score,    0)      AS avg_str_risk_score,
    COALESCE(str.max_str_risk_score,    0)      AS max_str_risk_score,
    COALESCE(str.high_confidence_strs,  0)      AS high_confidence_strs,
    COALESCE(str.medium_confidence_strs,0)      AS medium_confidence_strs,

    -- Derived compliance health flag
    CASE
        WHEN COALESCE(str.overdue_strs,       0) > 0  THEN 'CRITICAL'
        WHEN COALESCE(str.due_soon_strs,      0) > 0  THEN 'AT_RISK'
        WHEN COALESCE(cc.kyc_exceptions,      0) > 5  THEN 'NEEDS_ATTENTION'
        ELSE 'COMPLIANT'
    END                                                 AS branch_compliance_status,

    CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'        AS dbt_loaded_at

FROM {{ ref('dim_branches') }} b
LEFT JOIN branch_customer_agg  cc  ON b.branch_code = cc.branch_code
LEFT JOIN branch_ctr_agg       ctr ON b.branch_code = ctr.branch_code
LEFT JOIN branch_str_agg       str ON b.branch_code = str.branch_code

ORDER BY overdue_strs DESC, str_count DESC