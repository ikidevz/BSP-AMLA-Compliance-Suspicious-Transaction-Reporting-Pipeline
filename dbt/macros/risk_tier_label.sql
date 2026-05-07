-- Macro: risk_tier_label
-- Convert risk score to human-readable risk tier label
-- Used across AML models per BSP Circular 706

{% macro risk_tier_label(risk_score) %}

    CASE
        WHEN {{ risk_score }} >= 75 THEN 'HIGH'
        WHEN {{ risk_score }} >= 50 THEN 'MEDIUM'
        ELSE 'LOW'
    END

{% endmacro %}
