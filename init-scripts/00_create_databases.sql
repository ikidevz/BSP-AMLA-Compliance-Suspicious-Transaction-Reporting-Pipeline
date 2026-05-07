-- init-scripts/00_create_databases.sql
-- Create PostgreSQL databases for BSP/AMLA compliance pipeline
-- Runs as superuser during container initialization

-- Create main compliance database
CREATE DATABASE aml_compliance_db
    OWNER postgres
    ENCODING 'UTF8'
    LOCALE 'en_US.UTF-8'
    TEMPLATE template0;

-- Create Airflow database
CREATE DATABASE airflow_db
    OWNER postgres
    ENCODING 'UTF8'
    LOCALE 'en_US.UTF-8'
    TEMPLATE template0;

-- Create Metabase database
CREATE DATABASE metabase_db
    OWNER postgres
    ENCODING 'UTF8'
    LOCALE 'en_US.UTF-8'
    TEMPLATE template0;

\echo 'Databases created successfully'