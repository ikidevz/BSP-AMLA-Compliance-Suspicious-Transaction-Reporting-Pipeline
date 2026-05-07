-- init-scripts/06_setup_metabase_db.sql
-- Initialize Metabase database with proper permissions for Liquibase migrations
-- This allows metabase_amlc_user to create and manage the Liquibase changelog table and extensions

\connect airflow_db

-- Grant CREATE privilege on database (required for extensions like citext)
GRANT CREATE ON DATABASE airflow_db TO airflow_amlc_user;

-- Grant all privileges on the public schema to airflow_amlc_user so Liquibase can initialize
GRANT ALL PRIVILEGES ON SCHEMA public TO airflow_amlc_user;

-- Allow airflow_amlc_user to create objects in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO airflow_amlc_user;

-- Grant connection privileges
GRANT CONNECT ON DATABASE airflow_db TO airflow_amlc_user;

-- Ensure airflow_amlc_user can query existing tables
GRANT USAGE ON SCHEMA public TO airflow_amlc_user;

\echo 'Airflow database initialized successfully'
