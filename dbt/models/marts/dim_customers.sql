-- models/marts/dim_customers.sql
-- Dimension Table: dim_customers
-- Customer dimension with SCD Type 2 (tracks risk_tier changes)
-- PII masked per RA 10173


{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_dim_cust_current    ON {{ this }}(is_current) WHERE is_current = TRUE",
        "CREATE INDEX IF NOT EXISTS idx_dim_cust_risk_tier  ON {{ this }}(risk_tier, is_current)",
        "CREATE INDEX IF NOT EXISTS idx_dim_cust_valid_from ON {{ this }}(valid_from DESC)",
        "CREATE INDEX IF NOT EXISTS idx_dim_cust_pep        ON {{ this }}(is_pep) WHERE is_pep = TRUE"
    ]
) }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),

risk_rating AS (
    SELECT * FROM {{ ref('int_customer_risk_rating') }}
),

scd_customers AS (
    SELECT
        -- BIGSERIAL is not a castable type — use BIGINT
        ROW_NUMBER() OVER (ORDER BY c.customer_id)::BIGINT AS customer_sk,
        c.customer_id,

        -- PII masking per RA 10173
        -- Masked in this dim; use vw_dim_customers_masked for metabase_amlc_user
        CASE
            WHEN c.customer_name IS NOT NULL
            THEN SUBSTRING(c.customer_name, 1, 1)
                 || '***'
                 || SUBSTRING(c.customer_name, LENGTH(c.customer_name), 1)
            ELSE NULL
        END                                         AS customer_name,

        c.customer_type,
        c.customer_segment,

        -- SSS: last 4 digits only
        CASE
            WHEN c.sss_number IS NOT NULL THEN '***' || RIGHT(c.sss_number, 4)
            ELSE NULL
        END                                         AS sss_number,

        -- TIN: last 4 digits only
        CASE
            WHEN c.tin_number IS NOT NULL THEN '***' || RIGHT(c.tin_number, 4)
            ELSE NULL
        END                                         AS tin_number,

        c.date_of_birth,
        c.nationality,
        c.is_pep,
        c.pep_determination_date,
        c.risk_tier,
        c.account_status,
        c.account_opened_date,
        c.branch_code,

        -- Risk assessment from intermediate layer
        rr.overall_risk_score,
        rr.overall_risk_tier,
        rr.pep_risk_score,
        rr.customer_type_risk_score,
        rr.geography_risk_score,
        rr.kyc_health_risk_score,
        rr.account_status_risk_score,
        rr.watchlist_risk_score,
        rr.risk_factors,

        -- SCD Type 2 fields
        CURRENT_DATE::DATE      AS valid_from,
        NULL::DATE              AS valid_to,
        TRUE                    AS is_current,

        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila' AS dbt_loaded_at

    FROM customers c
    LEFT JOIN risk_rating rr
        ON c.customer_id = rr.customer_id
)

SELECT * FROM scd_customers
ORDER BY customer_id, valid_from