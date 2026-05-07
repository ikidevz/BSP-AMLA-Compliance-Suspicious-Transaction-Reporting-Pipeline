-- macros/ph_working_day_deadline.sql
-- Returns the Nth Philippine working day after a given start date.
-- Skips weekends and dates in seeds.ph_non_working_days.
-- Usage: {{ ph_working_day_deadline('sc.str_determination_ts::DATE', 5) }}

{% macro ph_working_day_deadline(start_date_expr, n_days) %}
(
    WITH _calendar_series AS (
        SELECT
            ({{ start_date_expr }} + (s.n || ' days')::INTERVAL)::DATE AS cal_date
        FROM GENERATE_SERIES(1, {{ n_days * 3 }}, 1) AS s(n)
    ),
    _working_days AS (
        SELECT
            cal_date,
            ROW_NUMBER() OVER (ORDER BY cal_date) AS working_day_rank
        FROM _calendar_series
        WHERE
            EXTRACT(DOW FROM cal_date) NOT IN (0, 6)  -- exclude weekends
            AND cal_date NOT IN (
                SELECT calendar_date
                FROM {{ source('seeds', 'ph_non_working_days') }}
            )
    )
    SELECT cal_date
    FROM _working_days
    WHERE working_day_rank = {{ n_days }}
    LIMIT 1
)
{% endmacro %}