-- models/marts/dim_branches.sql
-- Dimension Table: dim_branches

{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_dim_branches_code   ON {{ this }}(branch_code)",
        "CREATE INDEX IF NOT EXISTS idx_dim_branches_region ON {{ this }}(region_name)"
    ]
) }}

WITH branches AS (
    SELECT
        branch_code,
        branch_name,
        region_name,
        city_municipality,
        province
    FROM {{ source('seeds', 'ph_branches') }}
),

final AS (
    SELECT
        -- BIGSERIAL is a column definition type, not castable — use BIGINT
        ROW_NUMBER() OVER (ORDER BY branch_code)::BIGINT AS branch_sk,
        branch_code,
        branch_name,
        region_name,
        city_municipality,
        province,
        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila' AS dbt_loaded_at
    FROM branches
)

SELECT * FROM final
ORDER BY region_name, branch_name