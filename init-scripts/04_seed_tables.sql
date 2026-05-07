-- init-scripts/04_seed_tables.sql
-- Create and populate dbt seed reference tables
-- BSP/AMLA regulatory reference data

\connect aml_compliance_db

-- FATF Jurisdictions (blacklist/greylist)
CREATE TABLE IF NOT EXISTS bronze.fatf_jurisdictions (
    jurisdiction_code   VARCHAR(3) PRIMARY KEY,
    jurisdiction_name   VARCHAR(255) NOT NULL,
    fatf_status         VARCHAR(20)  NOT NULL CHECK (fatf_status IN ('BLACKLIST', 'GREYLIST', 'COMPLIANT')),
    risk_score          INT NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Philippine branches reference
CREATE TABLE IF NOT EXISTS bronze.ph_branches (
    branch_code         VARCHAR(10) PRIMARY KEY,
    branch_name         VARCHAR(255) NOT NULL,
    region_name         VARCHAR(100) NOT NULL,
    city_municipality   VARCHAR(100) NOT NULL,
    province            VARCHAR(100) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- AML risk weights (for scoring)
CREATE TABLE IF NOT EXISTS bronze.aml_risk_weights (
    risk_category   VARCHAR(50) PRIMARY KEY CHECK (risk_category IN ('GEOGRAPHY', 'PRODUCT', 'CHANNEL', 'CUSTOMER_TYPE', 'PEP')),
    risk_weight     INT NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- PH non-working days (holidays)
CREATE TABLE IF NOT EXISTS bronze.ph_non_working_days (
    holiday_date    DATE PRIMARY KEY,
    holiday_name    VARCHAR(255) NOT NULL,
    holiday_type    VARCHAR(50) CHECK (holiday_type IN ('NATIONAL', 'REGIONAL', 'SPECIAL')),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- STR indicators reference
CREATE TABLE IF NOT EXISTS bronze.str_indicators_ref (
    indicator_code          VARCHAR(20) PRIMARY KEY CHECK (indicator_code IN
        ('STRUCT_01', 'LAYER_01', 'JURIS_01', 'PEP_01', 'DORMANCY_01', 'ROUND_01', 'SMURFING_01', 'VELOCITY_01', 'KYC_01')),
    indicator_name          VARCHAR(255) NOT NULL,
    indicator_description   TEXT,
    base_risk_score         INT NOT NULL,
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Grants to aml_pipeline
GRANT SELECT ON bronze.fatf_jurisdictions  TO aml_pipeline;
GRANT SELECT ON bronze.ph_branches         TO aml_pipeline;
GRANT SELECT ON bronze.aml_risk_weights    TO aml_pipeline;
GRANT SELECT ON bronze.ph_non_working_days TO aml_pipeline;
GRANT SELECT ON bronze.str_indicators_ref  TO aml_pipeline;

-- Grants to airflow_amlc_user
GRANT SELECT ON bronze.fatf_jurisdictions  TO airflow_amlc_user;
GRANT SELECT ON bronze.ph_branches         TO airflow_amlc_user;
GRANT SELECT ON bronze.aml_risk_weights    TO airflow_amlc_user;
GRANT SELECT ON bronze.ph_non_working_days TO airflow_amlc_user;
GRANT SELECT ON bronze.str_indicators_ref  TO airflow_amlc_user;

-- Grants to metabase_amlc_user
GRANT SELECT ON bronze.fatf_jurisdictions  TO metabase_amlc_user;
GRANT SELECT ON bronze.ph_branches         TO metabase_amlc_user;
GRANT SELECT ON bronze.aml_risk_weights    TO metabase_amlc_user;
GRANT SELECT ON bronze.ph_non_working_days TO metabase_amlc_user;
GRANT SELECT ON bronze.str_indicators_ref  TO metabase_amlc_user;

\echo 'Seed tables created successfully'