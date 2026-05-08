-- init-scripts/05_setup_metabase_db.sql
-- Initialize Metabase database with proper permissions for Liquibase migrations
-- This allows metabase_amlc_user to create and manage the Liquibase changelog table and extensions

\connect metabase_db

-- Grant CREATE privilege on database (required for extensions like citext)
GRANT CREATE ON DATABASE metabase_db TO metabase_amlc_user;

-- Grant all privileges on the public schema to metabase_amlc_user so Liquibase can initialize
GRANT ALL PRIVILEGES ON SCHEMA public TO metabase_amlc_user;

-- Allow metabase_amlc_user to create objects in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO metabase_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO metabase_amlc_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO metabase_amlc_user;


-- Ensure metabase_amlc_user can query existing tables
GRANT USAGE ON SCHEMA public TO metabase_amlc_user;

\echo 'Metabase database initialized successfully'
