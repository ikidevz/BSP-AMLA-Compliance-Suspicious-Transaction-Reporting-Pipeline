-- init-scripts/01_create_roles.sql
-- Create PostgreSQL roles for BSP/AMLA compliance pipeline
-- Principle of least privilege per RA 10173 data governance
-- NOTE: Moved before 02_create_schemas.sql — schemas depend on these roles

-- Roles are global to PostgreSQL instance, no need to connect to specific database

DO $$
BEGIN
    -- Main pipeline role (read/write on staging, bronze, silver, gold)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'aml_pipeline') THEN
        CREATE ROLE aml_pipeline WITH
            LOGIN
            PASSWORD 'aml_pipeline_pwd'
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE;
    END IF;

    -- Read-only role for Metabase (gold schema only, masked data)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'metabase_amlc_user') THEN
        CREATE ROLE metabase_amlc_user WITH
            LOGIN
            PASSWORD 'metabase_amlc_password'
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE;
    END IF;

    -- Read-write role for Airflow orchestration
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'airflow_amlc_user') THEN
        CREATE ROLE airflow_amlc_user WITH
            LOGIN
            PASSWORD 'airflow_amlc_password'
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE;
    END IF;

    -- Audit role (append-only logs)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'audit_logger') THEN
        CREATE ROLE audit_logger WITH
            LOGIN
            PASSWORD 'audit_logger_pwd'
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE;
    END IF;

    -- Superuser for administrative tasks (limited use)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'admin_user') THEN
        CREATE ROLE admin_user WITH
            LOGIN
            SUPERUSER
            PASSWORD 'admin_user_pwd';
    END IF;
END
$$;

-- search_path assignments (ALTER ROLE is idempotent natively)
ALTER ROLE aml_pipeline  SET search_path = staging, bronze, silver, gold, public;
ALTER ROLE metabase_amlc_user   SET search_path = gold, public;
ALTER ROLE airflow_amlc_user  SET search_path = staging, bronze, silver, gold, public;
ALTER ROLE audit_logger  SET search_path = audit, public;

\echo 'Roles created successfully'