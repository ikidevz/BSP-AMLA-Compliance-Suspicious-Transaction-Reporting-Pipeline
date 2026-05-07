-- macros/apply_gold_rls.sql
-- Called via on-run-end in dbt_project.yml.
-- Idempotent: drops policies before recreating them.
{% macro apply_gold_rls() %}
 
    {% do run_query("ALTER TABLE IF EXISTS gold.dim_customers ENABLE ROW LEVEL SECURITY") %}
    {% do run_query("DROP POLICY IF EXISTS dim_customers_policy_admin ON gold.dim_customers") %}
    {% do run_query("DROP POLICY IF EXISTS dim_customers_policy_metabase ON gold.dim_customers") %}
    {% do run_query("CREATE POLICY dim_customers_policy_admin ON gold.dim_customers USING (current_user = 'admin_user')") %}
    {% do run_query("CREATE POLICY dim_customers_policy_metabase ON gold.dim_customers FOR SELECT USING (current_user = 'metabase_ro')") %}
    {% do run_query("REVOKE ALL ON gold.dim_customers FROM metabase_ro") %}
    {% do run_query("GRANT SELECT ON gold.vw_dim_customers_masked TO metabase_ro") %}
 
{% endmacro %}