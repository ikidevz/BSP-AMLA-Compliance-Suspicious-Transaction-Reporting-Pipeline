-- Intermediate model: int_kyc_health
-- KYC completeness and freshness scoring per BSP Circular 706 Part III
-- Purpose: Silver layer - KYC health monitoring for compliance dashboard

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
    ]
) }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),

kyc_docs AS (
    SELECT * FROM {{ ref('stg_kyc_documents') }}
),

-- KYC document completeness per customer
doc_completeness AS (
    SELECT
        c.customer_id,
        c.customer_type,
        c.risk_tier,
        c.is_pep,
        c.kyc_last_update_date,
        
        -- Track presence of key document types
        MAX(CASE WHEN kd.document_type IN ('PASSPORT', 'NATIONAL_ID', 'DRIVERS_LICENSE') THEN 1 ELSE 0 END) AS has_primary_id,
        MAX(CASE WHEN kd.document_type = 'POSTAL_ID' THEN 1 ELSE 0 END) AS has_address_verification,
        MAX(CASE WHEN kd.document_type IN ('NATIONAL_ID', 'PASSPORT') AND NOT kd.is_expired THEN 1 ELSE 0 END) AS has_valid_primary_id,
        
        -- Count non-expired documents
        COUNT(CASE WHEN NOT kd.is_expired THEN 1 END) AS valid_docs_count,
        COUNT(CASE WHEN kd.is_expired THEN 1 END) AS expired_docs_count,
        
        -- Check for documents expiring soon (90 days)
        MAX(CASE WHEN kd.expiry_within_90_days THEN 1 ELSE 0 END) AS has_docs_expiring_90d,
        MIN(kd.expiry_date) AS earliest_expiry_date
        
    FROM customers c
    LEFT JOIN kyc_docs kd
        ON c.customer_id = kd.customer_id
    GROUP BY c.customer_id, c.customer_type, c.risk_tier, c.is_pep, c.kyc_last_update_date
)

SELECT
    customer_id,
    customer_type,
    risk_tier,
    is_pep,
    kyc_last_update_date,
    
    -- KYC Completeness Score (0-100)
    -- Weights per BSP Circular 706
    ROUND(
        (
            -- Primary ID: 30 points
            COALESCE(has_primary_id, 0) * 30 +
            -- Valid (non-expired) primary ID: 20 points
            COALESCE(has_valid_primary_id, 0) * 20 +
            -- Address verification: 20 points
            COALESCE(has_address_verification, 0) * 20 +
            -- Multiple document types (completeness): 30 points
            CASE
                WHEN valid_docs_count >= 3 THEN 30
                WHEN valid_docs_count >= 2 THEN 20
                WHEN valid_docs_count >= 1 THEN 10
                ELSE 0
            END
        )::NUMERIC / 100,
        1
    ) AS kyc_completeness_score,
    
    -- KYC Freshness Flag per BSP Circular 706 Part III
    -- HIGH risk: 1 year refresh | MEDIUM: 3 years | LOW: 5 years
    CASE
        WHEN risk_tier = 'HIGH' AND kyc_last_update_date < CURRENT_DATE - INTERVAL '1 year' THEN TRUE
        WHEN risk_tier = 'MEDIUM' AND kyc_last_update_date < CURRENT_DATE - INTERVAL '3 years' THEN TRUE
        WHEN risk_tier = 'LOW' AND kyc_last_update_date < CURRENT_DATE - INTERVAL '5 years' THEN TRUE
        ELSE FALSE
    END AS kyc_freshness_flag,
    
    -- Days since KYC update
    (CURRENT_DATE - kyc_last_update_date)::INT AS days_since_kyc_update,
    
    -- Predicted KYC refresh due date
    CASE
        WHEN risk_tier = 'HIGH' THEN kyc_last_update_date + INTERVAL '1 year'
        WHEN risk_tier = 'MEDIUM' THEN kyc_last_update_date + INTERVAL '3 years'
        ELSE kyc_last_update_date + INTERVAL '5 years'
    END::DATE AS kyc_refresh_due_date,
    
    -- Document expiry alerts
    has_docs_expiring_90d,
    earliest_expiry_date,
    
    -- PEP Enhanced Due Diligence tracking
    CASE
        WHEN is_pep = TRUE THEN 'REQUIRES_SCREENING'
        ELSE 'NOT_APPLICABLE'
    END AS pep_screening_status,
    
    -- Summary flags for downstream compliance checks
    CASE
        WHEN kyc_completeness_score < 80 THEN TRUE
        ELSE FALSE
    END AS kyc_exception,
    
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at

FROM doc_completeness

ORDER BY kyc_completeness_score ASC, risk_tier DESC
