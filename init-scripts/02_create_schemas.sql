-- init-scripts/02_create_schemas.sql
-- Create schema structure for BSP/AMLA compliance pipeline
-- NOTE: Runs after 01_create_roles.sql — requires all roles to exist
-- RA 10173 compliant — principle of least privilege enforced per schema

\connect aml_compliance_db

-- ============================================================
-- SECTION 1: SCHEMA CREATION
-- All schemas owned by aml_pipeline (not postgres)
-- ============================================================

-- Staging schema: raw ingested data
CREATE SCHEMA IF NOT EXISTS staging AUTHORIZATION aml_pipeline;

-- Bronze schema: validated raw data
CREATE SCHEMA IF NOT EXISTS bronze AUTHORIZATION aml_pipeline;

-- Silver schema: business logic transformations
CREATE SCHEMA IF NOT EXISTS silver AUTHORIZATION aml_pipeline;

-- Gold schema: analytics-ready, compliant, masked for reporting
CREATE SCHEMA IF NOT EXISTS gold AUTHORIZATION aml_pipeline;

-- Audit schema: compliance logging (append-only)
CREATE SCHEMA IF NOT EXISTS audit AUTHORIZATION aml_pipeline;


-- ============================================================
-- SECTION 2: SCHEMA-LEVEL USAGE AND CREATE GRANTS
-- ============================================================

-- aml_pipeline: full ownership on all pipeline schemas
GRANT USAGE, CREATE ON SCHEMA staging, bronze, silver, gold TO aml_pipeline;
GRANT USAGE         ON SCHEMA audit                         TO aml_pipeline;

-- airflow_amlc_user: needs to create and read/write pipeline schemas
GRANT USAGE, CREATE ON SCHEMA staging, bronze, silver, gold TO airflow_amlc_user;

-- metabase_amlc_user: read-only, gold + public only
GRANT USAGE ON SCHEMA gold,   public TO metabase_amlc_user;

-- audit_logger: USAGE only on audit — no CREATE (cannot add tables)
GRANT USAGE ON SCHEMA audit TO audit_logger;


-- ============================================================
-- SECTION 3: TABLE AND SEQUENCE GRANTS ON EXISTING OBJECTS
-- Covers tables already created before this script runs
-- ============================================================

-- aml_pipeline
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA staging TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA bronze  TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA silver  TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA gold    TO aml_pipeline;
GRANT SELECT                         ON ALL TABLES    IN SCHEMA audit   TO aml_pipeline;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA staging TO aml_pipeline;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA bronze  TO aml_pipeline;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA silver  TO aml_pipeline;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA gold    TO aml_pipeline;

-- airflow_amlc_user
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA staging TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA bronze  TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA silver  TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA gold    TO airflow_amlc_user;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA staging TO airflow_amlc_user;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA bronze  TO airflow_amlc_user;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA silver  TO airflow_amlc_user;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA gold    TO airflow_amlc_user;

-- metabase_amlc_user: SELECT only on gold + public
GRANT SELECT ON ALL TABLES IN SCHEMA gold   TO metabase_amlc_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO metabase_amlc_user;

-- audit_logger: INSERT only on audit (strict append-only)
GRANT INSERT ON ALL TABLES IN SCHEMA audit TO audit_logger;


-- ============================================================
-- SECTION 4: DEFAULT PRIVILEGES
-- CRITICAL: Must be set as aml_pipeline (the schema owner)
-- because ALTER DEFAULT PRIVILEGES only applies to objects
-- created by the role that runs the statement.
-- Running as postgres here would silently do nothing useful.
-- ============================================================

SET ROLE aml_pipeline;

-- aml_pipeline future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronze  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA silver  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT USAGE, SELECT                  ON SEQUENCES TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronze  GRANT USAGE, SELECT                  ON SEQUENCES TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA silver  GRANT USAGE, SELECT                  ON SEQUENCES TO aml_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold    GRANT USAGE, SELECT                  ON SEQUENCES TO aml_pipeline;

-- airflow_amlc_user future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronze  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA silver  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT USAGE, SELECT                  ON SEQUENCES TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronze  GRANT USAGE, SELECT                  ON SEQUENCES TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA silver  GRANT USAGE, SELECT                  ON SEQUENCES TO airflow_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold    GRANT USAGE, SELECT                  ON SEQUENCES TO airflow_amlc_user;

-- metabase_amlc_user future tables in gold + public
ALTER DEFAULT PRIVILEGES IN SCHEMA gold   GRANT SELECT ON TABLES TO metabase_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO metabase_amlc_user;

-- audit_logger future tables in audit (INSERT only)
ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT INSERT ON TABLES TO audit_logger;

RESET ROLE;


-- ============================================================
-- SECTION 5: HARD REVOKES — RESTRICT ACCESS BY ROLE
-- ============================================================

-- metabase_amlc_user must never access raw/staging/audit schemas
REVOKE USAGE ON SCHEMA staging FROM metabase_amlc_user;
REVOKE USAGE ON SCHEMA bronze  FROM metabase_amlc_user;
REVOKE USAGE ON SCHEMA silver  FROM metabase_amlc_user;
REVOKE USAGE ON SCHEMA audit   FROM metabase_amlc_user;

-- audit_logger must never access pipeline schemas
REVOKE USAGE ON SCHEMA staging, bronze, silver, gold, public FROM audit_logger;

-- airflow must not touch audit schema
REVOKE USAGE ON SCHEMA audit FROM airflow_amlc_user;


-- ============================================================
-- SECTION 6: HARDEN PUBLIC SCHEMA AND SYSTEM DB DEFAULTS
-- ============================================================

-- Prevent any role from creating objects in public schema by default
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Prevent unprivileged connections to the postgres system database
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;


-- ============================================================
-- SECTION 7: VERIFICATION QUERIES (comment out in prod)
-- ============================================================

-- Uncomment to verify schema privileges after apply:
--
-- SELECT nspname AS schema,
--        pg_get_userbyid(nspowner) AS owner
-- FROM pg_namespace
-- WHERE nspname IN ('staging','bronze','silver','gold','audit')
-- ORDER BY nspname;
--
-- SELECT grantee, table_schema, privilege_type
-- FROM information_schema.role_table_grants
-- WHERE table_schema IN ('staging','bronze','silver','gold','audit')
--   AND grantee IN ('aml_pipeline','airflow_amlc_user','metabase_amlc_user','audit_logger')
-- ORDER BY grantee, table_schema, privilege_type;
--
-- SELECT pg_get_userbyid(defaclrole) AS grantor,
--        defaclobjtype,
--        defaclacl
-- FROM pg_default_acl
-- WHERE defaclnamespace IN (
--     SELECT oid FROM pg_namespace
--     WHERE nspname IN ('staging','bronze','silver','gold','audit')
-- );


\echo '===================================='
\echo 'Schemas and privileges applied successfully'
\echo '===================================='