-- Macro: ph_working_days_add
-- Add N Philippine working days to a given date
-- Used for AMLA 5-working-day STR filing deadline calculation (RA 9160 Sec 3(b-1))

{% macro ph_working_days_add(start_date, num_days) %}

    (
        WITH calendar_series AS (
            SELECT
                ({{ start_date }}::DATE + (n || ' days')::INTERVAL)::DATE AS calendar_date
            FROM GENERATE_SERIES(1, {{ num_days }} * 2, 1) AS n  -- Generate buffer of extra dates
        ),
        filtered_dates AS (
            SELECT
                calendar_date,
                ROW_NUMBER() OVER (ORDER BY calendar_date) AS working_day_rank
            FROM calendar_series
            WHERE EXTRACT(DOW FROM calendar_date) NOT IN (0, 6)  -- Exclude Sunday (0) and Saturday (6)
              AND calendar_date NOT IN (
                    SELECT calendar_date
                    FROM {{ source('seeds', 'ph_non_working_days') }}
                  )
        )
        SELECT calendar_date
        FROM filtered_dates
        WHERE working_day_rank = {{ num_days }}
        LIMIT 1
    )

{% endmacro %}
