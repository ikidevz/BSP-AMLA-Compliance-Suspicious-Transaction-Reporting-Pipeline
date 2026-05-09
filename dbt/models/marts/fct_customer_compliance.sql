-- models/marts/fct_customer_compliance.sql
-- Fact Table: fct_customer_compliance
-- Customer compliance snapshot — daily KYC and AML status

{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_fct_comp_customer      ON {{ this }}(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_fct_comp_snapshot_date ON {{ this }}(snapshot_date DESC)",
        "CREATE INDEX IF NOT EXISTS idx_fct_comp_risk_tier     ON {{ this }}(risk_tier) WHERE risk_tier IN ('HIGH', 'MEDIUM')",
        "CREATE INDEX IF NOT EXISTS idx_fct_comp_pep           ON {{ this }}(is_pep) WHERE is_pep = TRUE",
        "CREATE INDEX IF NOT EXISTS idx_fct_comp_kyc_exception ON {{ this }}(kyc_exception) WHERE kyc_exception = TRUE"
    ]
) }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),

kyc_health AS (
    SELECT * FROM {{ ref('int_kyc_health') }}
),

risk_rating AS (
    SELECT * FROM {{ ref('int_customer_risk_rating') }}
),

ctr_ytd AS (
    SELECT
        customer_id,
        COUNT(*) AS ctr_count_ytd
    FROM {{ ref('fct_covered_transactions') }}
    WHERE EXTRACT(YEAR FROM txn_date_ph) = EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY customer_id
),

str_ytd AS (
    SELECT
        customer_id,
        COUNT(*)                                                             AS str_count_ytd,
        SUM(CASE WHEN filing_urgency = 'OVERDUE' THEN 1 ELSE 0 END)        AS str_overdue_count
    FROM {{ ref('fct_suspicious_transactions') }}
    WHERE EXTRACT(YEAR FROM str_determination_ts) = EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY customer_id
)

SELECT
    c.customer_id,
    c.customer_type,
    c.customer_segment,
    c.branch_code,
    c.nationality,

    CURRENT_DATE                                    AS snapshot_date,

    -- KYC status (from int_kyc_health)
    kh.kyc_completeness_score,
    kh.kyc_freshness_flag,
    kh.kyc_exception,
    kh.days_since_kyc_update,
    kh.kyc_refresh_due_date,
    kh.has_primary_id,
    kh.has_address_verification,
    kh.has_valid_primary_id,
    kh.pep_screening_status,
    kh.earliest_expiry_date,

    -- Risk assessment (from int_customer_risk_rating)
    rr.overall_risk_score,
    rr.overall_risk_tier                            AS risk_tier,
    rr.pep_risk_score,
    rr.customer_type_risk_score,
    rr.geography_risk_score,
    rr.kyc_health_risk_score,
    rr.account_status_risk_score,
    rr.watchlist_risk_score,

    -- AML activity YTD
    COALESCE(ctr.ctr_count_ytd,       0)           AS ctr_count_ytd,
    COALESCE(str.str_count_ytd,       0)           AS str_count_ytd,
    COALESCE(str.str_overdue_count,   0)           AS str_overdue_count_ytd,

    -- Key flags
    c.is_pep,
    c.account_status,
    c.kyc_last_update_date,

    CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'   AS dbt_loaded_at

FROM customers c
LEFT JOIN kyc_health   kh  ON c.customer_id = kh.customer_id
LEFT JOIN risk_rating  rr  ON c.customer_id = rr.customer_id
LEFT JOIN ctr_ytd      ctr ON c.customer_id = ctr.customer_id
LEFT JOIN str_ytd      str ON c.customer_id = str.customer_id

ORDER BY c.customer_id