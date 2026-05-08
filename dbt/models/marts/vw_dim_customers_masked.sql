-- models/marts/vw_dim_customers_masked.sql
-- Masked customer view for Metabase and restricted reporting access.
{{ config(
    materialized='view',
    schema='gold',
    alias='vw_dim_customers_masked'
) }}

SELECT
    customer_sk,
    customer_id,
    CASE
        WHEN current_user = 'metabase_amlc_user' AND customer_name IS NOT NULL
        THEN SUBSTRING(customer_name, 1, 1) || '***' || SUBSTRING(customer_name, LENGTH(customer_name), 1)
        ELSE customer_name
    END AS customer_name,
    customer_type,
    customer_segment,
    CASE
        WHEN current_user = 'metabase_amlc_user' AND sss_number IS NOT NULL
        THEN '***' || RIGHT(sss_number, 4)
        ELSE sss_number
    END AS sss_number,
    CASE
        WHEN current_user = 'metabase_amlc_user' AND tin_number IS NOT NULL
        THEN '***' || RIGHT(tin_number, 4)
        ELSE tin_number
    END AS tin_number,
    birth_date,
    nationality,
    is_pep,
    pep_determination_date,
    risk_tier,
    account_status,
    account_opened_date,
    branch_code,
    overall_risk_score,
    overall_risk_tier,
    pep_risk_score,
    customer_type_risk_score,
    geography_risk_score,
    kyc_health_risk_score,
    account_status_risk_score,
    watchlist_risk_score,
    risk_factors,
    valid_from,
    valid_to,
    is_current,
    dbt_loaded_at
FROM {{ ref('dim_customers') }};
