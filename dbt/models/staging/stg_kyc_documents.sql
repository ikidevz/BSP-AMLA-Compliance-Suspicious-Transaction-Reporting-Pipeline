-- Staging model: stg_kyc_documents
-- KYC document records with expiry tracking
-- Purpose: Bronze layer - document lifecycle management for KYC refresh monitoring

{{ config(
    materialized='table',
    schema='bronze',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['document_type']},
        {'columns': ['expiry_date']},
    ]
) }}

WITH raw_kyc AS (
    SELECT
        document_id,
        customer_id,
        document_type,
        document_number,
        issue_date,
        expiry_date,
        issuing_country,
        issuing_authority,
        created_at,
        updated_at
    FROM {{ source('staging', 'raw_kyc_documents') }}
)

SELECT
    -- Primary key
    raw_kyc.document_id,
    
    -- Foreign key
    TRIM(raw_kyc.customer_id)::VARCHAR(50) AS customer_id,
    
    -- Document attributes
    UPPER(TRIM(raw_kyc.document_type))::VARCHAR AS document_type,
    TRIM(raw_kyc.document_number)::VARCHAR AS document_number,
    UPPER(TRIM(raw_kyc.issuing_country))::CHAR(2) AS issuing_country,
    TRIM(raw_kyc.issuing_authority)::VARCHAR AS issuing_authority,
    
    -- Dates
    raw_kyc.issue_date::DATE AS issue_date,
    raw_kyc.expiry_date::DATE AS expiry_date,
    
    -- Calculated fields for KYC refresh monitoring (per BSP Circ 706)
    -- HIGH risk: 1 year refresh | MEDIUM: 3 years | LOW: 5 years
    CASE
        WHEN raw_kyc.expiry_date IS NULL THEN NULL
        ELSE (raw_kyc.expiry_date - CURRENT_DATE)::INT
    END AS days_until_expiry,
    
    CASE
        WHEN raw_kyc.expiry_date IS NULL THEN FALSE
        ELSE raw_kyc.expiry_date < CURRENT_DATE
    END AS is_expired,
    
    CASE
        WHEN raw_kyc.expiry_date IS NULL THEN FALSE
        ELSE raw_kyc.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'
    END AS expiry_within_90_days,
    
    -- Audit columns
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at
    
FROM raw_kyc

-- Data quality: Keep only documents with customer and document type
WHERE raw_kyc.customer_id IS NOT NULL
  AND raw_kyc.document_type IS NOT NULL
  AND raw_kyc.issue_date IS NOT NULL
