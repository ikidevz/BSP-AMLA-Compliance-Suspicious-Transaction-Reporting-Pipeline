-- init-scripts/02_create_schemas.sql
-- Create schema structure for BSP/AMLA compliance pipeline
-- NOTE: Runs after 01_create_roles.sql — requires aml_pipeline role to exist

\connect aml_compliance_db

-- Staging schema: raw ingested data
CREATE SCHEMA IF NOT EXISTS staging AUTHORIZATION aml_pipeline;
GRANT USAGE  ON SCHEMA staging TO aml_pipeline;
GRANT CREATE ON SCHEMA staging TO aml_pipeline;
GRANT USAGE  ON SCHEMA staging TO airflow_amlc_user;
GRANT CREATE ON SCHEMA staging TO airflow_amlc_user;

-- Bronze schema: validated raw data
CREATE SCHEMA IF NOT EXISTS bronze AUTHORIZATION aml_pipeline;
GRANT USAGE  ON SCHEMA bronze TO aml_pipeline;
GRANT CREATE ON SCHEMA bronze TO aml_pipeline;
GRANT USAGE  ON SCHEMA bronze TO airflow_amlc_user;
GRANT CREATE ON SCHEMA bronze TO airflow_amlc_user;

-- Silver schema: business logic transformations
CREATE SCHEMA IF NOT EXISTS silver AUTHORIZATION aml_pipeline;
GRANT USAGE  ON SCHEMA silver TO aml_pipeline;
GRANT CREATE ON SCHEMA silver TO aml_pipeline;
GRANT USAGE  ON SCHEMA silver TO airflow_amlc_user;
GRANT CREATE ON SCHEMA silver TO airflow_amlc_user;

-- Gold schema: analytics-ready, compliant
CREATE SCHEMA IF NOT EXISTS gold AUTHORIZATION aml_pipeline;
GRANT USAGE  ON SCHEMA gold TO aml_pipeline;
GRANT CREATE ON SCHEMA gold TO aml_pipeline;
GRANT USAGE  ON SCHEMA gold TO airflow_amlc_user;
GRANT CREATE ON SCHEMA gold TO airflow_amlc_user;
GRANT USAGE  ON SCHEMA gold TO metabase_amlc_user;

-- Audit schema: compliance logging
CREATE SCHEMA IF NOT EXISTS audit AUTHORIZATION aml_pipeline;
GRANT USAGE  ON SCHEMA audit TO aml_pipeline;
GRANT CREATE ON SCHEMA audit TO aml_pipeline;
GRANT USAGE  ON SCHEMA audit TO audit_logger;
GRANT CREATE ON SCHEMA audit TO audit_logger;

\echo 'Schemas created successfully'