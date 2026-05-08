-- init-scripts/07_setup_dbt.sql
-- Initialize dbt database with proper permissions

\connect aml_compliance_db


-- Grant CREATE privilege on database (required for extensions like citext)
GRANT CREATE ON DATABASE aml_compliance_db TO aml_pipeline;

-- Grant all privileges on the public schema to aml_pipeline so Liquibase can initialize
GRANT ALL PRIVILEGES ON SCHEMA public TO aml_pipeline;

-- Allow aml_pipeline to create objects in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO aml_pipeline;

-- Grant connection privileges
GRANT CONNECT ON DATABASE metabase_db TO aml_pipeline;

-- Ensure aml_pipeline can query existing tables
GRANT USAGE ON SCHEMA public TO aml_pipeline;

\echo 'Dbt roles initialized successfully'
