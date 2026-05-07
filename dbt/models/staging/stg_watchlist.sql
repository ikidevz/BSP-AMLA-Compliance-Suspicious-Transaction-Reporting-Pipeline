-- Staging model: stg_watchlist
-- Watchlist and sanctions screening results
-- Purpose: Bronze layer - screening outcome normalization

{{ config(
    materialized='table',
    schema='bronze',
    indexes=[
        {'columns': ['customer_id']},
        {'columns': ['screening_date']},
        {'columns': ['match_status']},
    ]
) }}

WITH raw_wl AS (
    SELECT
        screening_id,
        customer_id,
        screening_date,
        watchlist_source,
        match_status,
        matched_name,
        match_score,
        match_confidence_pct,
        notes,
        created_at,
        updated_at
    FROM {{ source('staging', 'raw_watchlist_screening') }}
)

SELECT
    -- Primary key
    raw_wl.screening_id,
    
    -- Foreign key
    TRIM(raw_wl.customer_id)::VARCHAR(50) AS customer_id,
    
    -- Screening details
    raw_wl.screening_date::DATE AS screening_date,
    
    UPPER(TRIM(raw_wl.watchlist_source))::VARCHAR AS watchlist_source,
    
    -- Match result (per AMLC/OFAC protocols)
    UPPER(TRIM(raw_wl.match_status))::VARCHAR AS match_status,
    
    TRIM(raw_wl.matched_name)::VARCHAR AS matched_name,
    
    CAST(raw_wl.match_score AS NUMERIC(5, 2)) AS match_score,
    
    CAST(raw_wl.match_confidence_pct AS NUMERIC(5, 2)) AS match_confidence_pct,
    
    TRIM(raw_wl.notes)::VARCHAR AS notes,
    
    -- Flags for downstream STR detection
    CASE
        WHEN UPPER(TRIM(raw_wl.match_status)) IN ('CONFIRMED_MATCH', 'POSSIBLE_MATCH') THEN TRUE
        ELSE FALSE
    END AS is_potential_match,
    
    CASE
        WHEN UPPER(TRIM(raw_wl.watchlist_source)) = 'UN_SANCTIONS'
             AND UPPER(TRIM(raw_wl.match_status)) = 'CONFIRMED_MATCH' THEN TRUE
        WHEN UPPER(TRIM(raw_wl.watchlist_source)) = 'OFAC_SDN'
             AND UPPER(TRIM(raw_wl.match_status)) = 'CONFIRMED_MATCH' THEN TRUE
        ELSE FALSE
    END AS is_sanctions_confirmed,
    
    -- Audit columns
    CURRENT_TIMESTAMP::TIMESTAMP WITH TIME ZONE AS dbt_loaded_at
    
FROM raw_wl

-- Data quality
WHERE raw_wl.customer_id IS NOT NULL
  AND raw_wl.screening_date IS NOT NULL
