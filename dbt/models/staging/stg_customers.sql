-- Staging model: stg_customers
-- Normalize customer master with KYC profile
-- Purpose: Bronze layer - customer dimension normalization

{{ config(
    materialized='table',
    schema='bronze',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['branch_code']},
        {'columns': ['is_pep']},
    ]
) }}

WITH raw_cust AS (
    SELECT
        customer_id,
        customer_name,
        customer_type,
        sss_number,
        tin_number,
        philhealth_id,
        date_of_birth,
        nationality,
        is_pep,
        pep_determination_date,
        risk_tier,
        account_status,
        account_opened_date,
        branch_code,
        customer_segment,
        kyc_status,
        kyc_last_update_date,
        created_at,
        updated_at
    FROM {{ source('staging', 'raw_customers') }}
)

SELECT
    -- Primary key
    TRIM(raw_cust.customer_id)::VARCHAR(50) AS customer_id,
    
    -- Customer name (full PII - will be masked at Silver)
    TRIM(raw_cust.customer_name)::VARCHAR AS customer_name,
    
    -- Customer classification
    UPPER(TRIM(raw_cust.customer_type))::VARCHAR AS customer_type,
    UPPER(TRIM(raw_cust.customer_segment))::VARCHAR AS customer_segment,
    
    -- Identification documents (full PII - will be masked at Silver)
    TRIM(raw_cust.sss_number)::VARCHAR AS sss_number,
    TRIM(raw_cust.tin_number)::VARCHAR AS tin_number,
    TRIM(raw_cust.philhealth_id)::VARCHAR AS philhealth_id,
    
    -- Demographics
    raw_cust.date_of_birth::DATE AS date_of_birth,
    UPPER(TRIM(raw_cust.nationality))::CHAR(2) AS nationality,
    
    -- AML Risk Assessment per BSP Circular 706
    CASE
        WHEN raw_cust.is_pep = TRUE THEN 'HIGH'
        WHEN UPPER(raw_cust.risk_tier) IN ('HIGH') THEN 'HIGH'
        WHEN UPPER(raw_cust.risk_tier) IN ('MEDIUM', 'MED') THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_tier,
    
    -- PEP Status (Politically Exposed Person - BSP Circ 706 Part III)
    COALESCE(raw_cust.is_pep, FALSE)::BOOLEAN AS is_pep,
    raw_cust.pep_determination_date::DATE AS pep_determination_date,
    
    -- Account status
    UPPER(TRIM(raw_cust.account_status))::VARCHAR AS account_status,
    raw_cust.account_opened_date::DATE AS account_opened_date,
    
    -- Organization
    TRIM(raw_cust.branch_code)::VARCHAR(10) AS branch_code,
    
    -- KYC Status
    UPPER(TRIM(raw_cust.kyc_status))::VARCHAR AS kyc_status,
    raw_cust.kyc_last_update_date::DATE AS kyc_last_update_date,
    
    -- Audit columns
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at
    
FROM raw_cust

-- Data quality checks
WHERE raw_cust.customer_id IS NOT NULL
  AND raw_cust.customer_name IS NOT NULL
  AND raw_cust.account_opened_date IS NOT NULL
