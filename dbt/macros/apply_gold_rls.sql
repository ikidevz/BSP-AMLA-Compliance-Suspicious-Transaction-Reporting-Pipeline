{% macro apply_gold_rls() %}

    {% set table_exists_query %}
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'gold'
            AND table_name = 'dim_customers'
        )
    {% endset %}

    {% if execute %}
        {% set result = run_query(table_exists_query) %}
        {% set exists = result.rows[0][0] %}

        {% if exists %}
            {% do run_query("ALTER TABLE IF EXISTS gold.dim_customers ENABLE ROW LEVEL SECURITY") %}
            {% do run_query("DROP POLICY IF EXISTS dim_customers_policy_admin ON gold.dim_customers") %}
            {% do run_query("DROP POLICY IF EXISTS dim_customers_policy_metabase ON gold.dim_customers") %}
            {% do run_query("CREATE POLICY dim_customers_policy_admin ON gold.dim_customers USING (current_user = 'admin_user')") %}
            {% do run_query("CREATE POLICY dim_customers_policy_metabase ON gold.dim_customers FOR SELECT USING (current_user = 'metabase_amlc_user')") %}
            {% do run_query("REVOKE ALL ON gold.dim_customers FROM metabase_amlc_user") %}
            {% do run_query("GRANT SELECT ON gold.vw_dim_customers_masked TO metabase_amlc_user") %}
        {% else %}
            {{ log("apply_gold_rls: gold.dim_customers not found, skipping RLS.", info=True) }}
        {% endif %}

    {% endif %}

{% endmacro %}