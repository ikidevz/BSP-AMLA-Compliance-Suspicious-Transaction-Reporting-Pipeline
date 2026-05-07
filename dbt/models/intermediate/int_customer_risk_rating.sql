-- Intermediate model: int_customer_risk_rating
-- Integrated customer risk score calculation per BSP Circular 706 Part III
-- Purpose: Silver layer - AML risk assessment for customer dimension

{{ config(
    materialized='table',
    schema='silver',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['overall_risk_tier']},
    ]
) }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),

kyc_health AS (
    SELECT * FROM {{ ref('int_kyc_health') }}
),

watchlist_hits AS (
    SELECT
        customer_id,
        COUNT(*) AS total_watchlist_hits,
        SUM(CASE WHEN is_sanctions_confirmed THEN 1 ELSE 0 END) AS confirmed_sanctions_hits,
        SUM(CASE WHEN is_potential_match THEN 1 ELSE 0 END) AS potential_match_count,
        MAX(match_confidence_pct) AS highest_match_confidence
    FROM {{ ref('stg_watchlist') }}
    GROUP BY customer_id
),

-- Risk weights from seeds
risk_weights AS (
    SELECT * FROM {{ source('seeds', 'aml_risk_weights') }}
),

-- Calculate composite risk score
risk_calculation AS (
    SELECT
        c.customer_id,
        c.customer_type,
        c.customer_segment,
        c.risk_tier,
        c.is_pep,
        c.nationality,
        c.account_status,
        
        -- Components of risk score
        
        -- 1. PEP Risk (0-75 points)
        CASE
            WHEN c.is_pep = TRUE THEN
                COALESCE(rw.weight_value, 75)
            ELSE 0
        END AS pep_risk_score,
        
        -- 2. Customer Type Risk (0-35 points)
        CASE
            WHEN c.customer_type = 'CORPORATE' THEN 20
            WHEN c.customer_type = 'INDIVIDUAL' THEN 30
            WHEN c.customer_type = 'SOLEPROPRIETOR' THEN 35
            WHEN c.customer_type = 'NGO' THEN 10
            WHEN c.customer_type = 'GOVERNMENT' THEN 5
            ELSE 25
        END AS customer_type_risk_score,
        
        -- 3. Geography Risk (0-90 points) - based on FATF jurisdictions
        CASE
            WHEN c.nationality IN ('KP', 'IR', 'SY') THEN 90  -- FATF blacklist
            WHEN c.nationality IN ('BY', 'JO', 'LB', 'PA', 'TR', 'ZA') THEN 50  -- FATF greylist
            ELSE 10
        END AS geography_risk_score,
        
        -- 4. KYC Health Risk (0-40 points)
        CASE
            WHEN kh.kyc_completeness_score < 60 THEN 40
            WHEN kh.kyc_completeness_score < 80 THEN 25
            WHEN kh.kyc_completeness_score < 90 THEN 15
            ELSE 5
        END AS kyc_health_risk_score,
        
        -- 5. Account Status Risk (0-30 points)
        CASE
            WHEN c.account_status = 'FROZEN' THEN 30
            WHEN c.account_status = 'RESTRICTED' THEN 25
            WHEN c.account_status = 'DORMANT' THEN 15
            WHEN c.account_status = 'ACTIVE' THEN 0
            WHEN c.account_status = 'CLOSED' THEN 0
            ELSE 10
        END AS account_status_risk_score,
        
        -- 6. Watchlist Hit Risk (0-50 points)
        CASE
            WHEN COALESCE(wh.confirmed_sanctions_hits, 0) > 0 THEN 50
            WHEN COALESCE(wh.highest_match_confidence, 0) > 75 THEN 40
            WHEN COALESCE(wh.highest_match_confidence, 0) > 50 THEN 20
            WHEN COALESCE(wh.total_watchlist_hits, 0) > 0 THEN 15
            ELSE 0
        END AS watchlist_risk_score,
        
        kh.kyc_completeness_score,
        COALESCE(wh.total_watchlist_hits, 0) AS watchlist_hit_count
        
    FROM customers c
    LEFT JOIN kyc_health kh
        ON c.customer_id = kh.customer_id
    LEFT JOIN watchlist_hits wh
        ON c.customer_id = wh.customer_id
    LEFT JOIN risk_weights rw
        ON rw.risk_category = 'PEP'
        AND rw.risk_subcategory = 'PEP_CUSTOMER'
)

SELECT
    customer_id,
    customer_type,
    customer_segment,
    risk_tier,
    is_pep,
    nationality,
    account_status,
    
    -- Risk score components
    pep_risk_score,
    customer_type_risk_score,
    geography_risk_score,
    kyc_health_risk_score,
    account_status_risk_score,
    watchlist_risk_score,
    
    -- Overall Risk Score (0-100 scale)
    LEAST(
        100,
        ROUND((
            pep_risk_score +
            customer_type_risk_score +
            geography_risk_score +
            kyc_health_risk_score +
            account_status_risk_score +
            watchlist_risk_score
        )::NUMERIC / 5, 0)  -- Normalized to 0-100
    )::INT AS overall_risk_score,
    
    -- Risk Tier Classification per BSP Circular 706
    CASE
        WHEN (
            pep_risk_score +
            customer_type_risk_score +
            geography_risk_score +
            kyc_health_risk_score +
            account_status_risk_score +
            watchlist_risk_score
        ) / 5 >= 75 THEN 'HIGH'
        WHEN (
            pep_risk_score +
            customer_type_risk_score +
            geography_risk_score +
            kyc_health_risk_score +
            account_status_risk_score +
            watchlist_risk_score
        ) / 5 >= 50 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS overall_risk_tier,
    
    -- Risk factors present
    ARRAY_REMOVE(ARRAY[
        CASE WHEN is_pep = TRUE THEN 'PEP' END,
        CASE WHEN account_status = 'FROZEN' THEN 'FROZEN_ACCOUNT' END,
        CASE WHEN watchlist_hit_count > 0 THEN 'WATCHLIST_HIT' END,
        CASE WHEN kyc_completeness_score < 80 THEN 'INCOMPLETE_KYC' END
    ], NULL) AS risk_factors,
    
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at

FROM risk_calculation

ORDER BY overall_risk_score DESC
