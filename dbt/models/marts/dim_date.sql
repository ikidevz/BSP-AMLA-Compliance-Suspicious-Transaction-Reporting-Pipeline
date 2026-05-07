-- models/marts/dim_date.sql
-- Dimension Table: dim_date
-- Philippine fiscal calendar with working day flags
-- Used for AMLA 5-working-day deadline calculations

{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_dim_date_lookup     ON {{ this }}(calendar_date)",
        "CREATE INDEX IF NOT EXISTS idx_dim_date_ph_working ON {{ this }}(is_ph_working_day, calendar_date)",
        "CREATE INDEX IF NOT EXISTS idx_dim_date_month      ON {{ this }}(calendar_year, calendar_month)"
    ]
) }}

WITH date_spine AS (
    SELECT
        (CURRENT_DATE - INTERVAL '5 years')::DATE
            + (n || ' days')::INTERVAL AS calendar_date
    FROM GENERATE_SERIES(0, 5 * 365, 1) AS n
),

ph_holidays AS (
    -- Materialise holiday list once to avoid repeated subquery scans
    SELECT calendar_date AS holiday_date
    FROM {{ source('seeds', 'ph_non_working_days') }}
),

calendar AS (
    SELECT
        TO_CHAR(d.calendar_date, 'YYYYMMDD')::INTEGER   AS date_id,
        d.calendar_date,

        -- Standardised column names (used in post_hook indexes above)
        EXTRACT(YEAR    FROM d.calendar_date)::INT       AS calendar_year,
        EXTRACT(MONTH   FROM d.calendar_date)::INT       AS calendar_month,
        EXTRACT(QUARTER FROM d.calendar_date)::INT       AS calendar_quarter,
        EXTRACT(DAY     FROM d.calendar_date)::INT       AS day_of_month,

        -- Postgres DOW: 0=Sunday, 1=Monday … 6=Saturday (not ISO 8601)
        EXTRACT(DOW FROM d.calendar_date)::INT           AS day_of_week,

        CASE EXTRACT(DOW FROM d.calendar_date)
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
        END                                              AS day_name,

        -- PH working day: Mon–Fri excluding PH holidays
        CASE
            WHEN EXTRACT(DOW FROM d.calendar_date) NOT IN (0, 6)
             AND h.holiday_date IS NULL
            THEN TRUE
            ELSE FALSE
        END                                              AS is_ph_working_day,

        -- Current period flags (useful for Metabase relative filters)
        CASE
            WHEN d.calendar_date >= DATE_TRUNC('week', CURRENT_DATE)::DATE
             AND d.calendar_date <  DATE_TRUNC('week', CURRENT_DATE)::DATE + INTERVAL '7 days'
            THEN TRUE ELSE FALSE
        END                                              AS is_current_week,

        CASE
            WHEN EXTRACT(YEAR  FROM d.calendar_date) = EXTRACT(YEAR  FROM CURRENT_DATE)
             AND EXTRACT(MONTH FROM d.calendar_date) = EXTRACT(MONTH FROM CURRENT_DATE)
            THEN TRUE ELSE FALSE
        END                                              AS is_current_month,

        CASE
            WHEN EXTRACT(YEAR FROM d.calendar_date) = EXTRACT(YEAR FROM CURRENT_DATE)
            THEN TRUE ELSE FALSE
        END                                              AS is_current_year,

        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'    AS dbt_loaded_at

    FROM date_spine d
    LEFT JOIN ph_holidays h
        ON d.calendar_date = h.holiday_date
)

SELECT * FROM calendar
ORDER BY calendar_date