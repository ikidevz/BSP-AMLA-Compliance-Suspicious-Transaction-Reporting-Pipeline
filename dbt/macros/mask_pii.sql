-- Macro: mask_pii
-- Mask personally identifiable information per RA 10173 (Philippine Data Privacy Act)
-- Rules:
--   - Names: First initial + last 2 characters
--   - Account numbers: Last 4 digits only
--   - Document numbers: Last 4 digits only
--   - Emails: First char + *** + domain

{% macro mask_pii(pii_value, pii_type='name') %}

    CASE
        WHEN {{ pii_type }} = 'name' AND {{ pii_value }} IS NOT NULL THEN
            SUBSTRING({{ pii_value }}, 1, 1) || '***' ||
            SUBSTRING({{ pii_value }}, LENGTH({{ pii_value }}) - 1, 2)
        
        WHEN {{ pii_type }} = 'account' AND {{ pii_value }} IS NOT NULL THEN
            '***' || RIGHT({{ pii_value }}, 4)
        
        WHEN {{ pii_type }} = 'document' AND {{ pii_value }} IS NOT NULL THEN
            '***' || RIGHT({{ pii_value }}, 4)
        
        WHEN {{ pii_type }} = 'email' AND {{ pii_value }} IS NOT NULL THEN
            SUBSTRING({{ pii_value }}, 1, 1) || '***@' ||
            SUBSTRING({{ pii_value }}, POSITION('@' IN {{ pii_value }}) + 1)
        
        WHEN {{ pii_type }} = 'phone' AND {{ pii_value }} IS NOT NULL THEN
            '***' || RIGHT({{ pii_value }}, 4)
        
        ELSE NULL
    END

{% endmacro %}
