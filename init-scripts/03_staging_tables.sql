-- init-scripts/03_staging_tables.sql
-- Create raw staging tables for data ingestion
-- RA 9160 (AMLA) requires 10-year transaction retention

\connect aml_compliance_db

-- Raw transactions table (per generate_transactions.py schema)
CREATE TABLE IF NOT EXISTS staging.raw_transactions (
    txn_id                  UUID DEFAULT gen_random_uuid(),
    customer_id             VARCHAR(50) NOT NULL,
    branch_code             VARCHAR(10) NOT NULL,
    txn_date_ph             DATE NOT NULL,
    txn_time_ph             TIME NOT NULL,
    txn_type                VARCHAR(20) NOT NULL CHECK (txn_type IN ('CASH', 'RTGS', 'PESONet', 'InstaPay')),
    txn_channel             VARCHAR(20) NOT NULL CHECK (txn_channel IN ('BRANCH', 'ATM', 'ONLINE', 'MOBILE')),
    transaction_direction   VARCHAR(10) NOT NULL CHECK (transaction_direction IN ('DEBIT', 'CREDIT')),
    amount_local            NUMERIC(15, 2) NOT NULL,
    currency_code           CHAR(3) NOT NULL DEFAULT 'PHP',
    amount_php              NUMERIC(15, 2) NOT NULL,
    counterparty_name       VARCHAR(255),
    counterparty_account    VARCHAR(20),
    counterparty_bank       VARCHAR(50),
    purpose_code            VARCHAR(10),
    purpose_description     TEXT,
    reference_number        VARCHAR(50),
    source_system           VARCHAR(50) DEFAULT 'TEMENOS',
    batch_id                VARCHAR(50),
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (txn_id, txn_date_ph)
) PARTITION BY RANGE (txn_date_ph);

-- Create yearly partitions for 10-year historical retention (RA 9160)
DO $$
DECLARE
    start_year INT := 2015;
    end_year   INT := 2035;
    cur_year   INT;
BEGIN
    FOR cur_year IN start_year..end_year LOOP
        BEGIN
            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS staging.raw_transactions_%s
                 PARTITION OF staging.raw_transactions
                 FOR VALUES FROM (%L) TO (%L)',
                cur_year,
                cur_year::TEXT || '-01-01',
                (cur_year + 1)::TEXT || '-01-01'
            );
        EXCEPTION WHEN OTHERS THEN
            NULL; -- Partition already exists
        END;
    END LOOP;
END $$;

-- Raw customers table (per generate_customers.py schema)
CREATE TABLE IF NOT EXISTS staging.raw_customers (
    customer_id             VARCHAR(50) PRIMARY KEY,
    customer_name           VARCHAR(255) NOT NULL,
    customer_type           VARCHAR(50)  NOT NULL CHECK (customer_type IN ('INDIVIDUAL', 'CORPORATE', 'SOLEPROPRIETOR', 'NGO')),
    sss_number              VARCHAR(20),
    tin_number              VARCHAR(20),
    philhealth_id           VARCHAR(20),
    date_of_birth           DATE,
    nationality             CHAR(2),
    is_pep                  BOOLEAN NOT NULL DEFAULT FALSE,
    pep_determination_date  DATE,
    risk_tier               VARCHAR(20) NOT NULL CHECK (risk_tier IN ('HIGH', 'MEDIUM', 'LOW')),
    account_status          VARCHAR(20) NOT NULL CHECK (account_status IN ('ACTIVE', 'DORMANT', 'RESTRICTED', 'CLOSED', 'FROZEN')),
    account_opened_date     DATE NOT NULL,
    branch_code             VARCHAR(10) NOT NULL,
    customer_segment        VARCHAR(20) CHECK (customer_segment IN ('RETAIL', 'SME', 'CORPORATE')),
    kyc_status              VARCHAR(20) DEFAULT 'COMPLETE',
    kyc_last_update_date    DATE,
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Raw KYC documents table (per generate_kyc.py schema)
CREATE TABLE IF NOT EXISTS staging.raw_kyc_documents (
    document_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id         VARCHAR(50) NOT NULL REFERENCES staging.raw_customers(customer_id),
    document_type       VARCHAR(50) NOT NULL CHECK (document_type IN ('PASSPORT', 'NATIONAL_ID', 'DRIVERS_LICENSE', 'POSTAL_ID')),
    document_number     VARCHAR(50) NOT NULL,
    issue_date          DATE NOT NULL,
    expiry_date         DATE,
    issuing_country     CHAR(2),
    issuing_authority   VARCHAR(255),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Raw watchlist/sanctions screening table
CREATE TABLE IF NOT EXISTS staging.raw_watchlist_screening (
    screening_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             VARCHAR(50) NOT NULL REFERENCES staging.raw_customers(customer_id),
    screening_date          DATE NOT NULL,
    watchlist_source        VARCHAR(100) NOT NULL CHECK (watchlist_source IN ('AMLC', 'UN_SANCTIONS', 'OFAC_SDN', 'INTERNAL_BLACKLIST')),
    match_status            VARCHAR(50)  NOT NULL CHECK (match_status IN ('CONFIRMED_MATCH', 'POSSIBLE_MATCH', 'FALSE_POSITIVE', 'NO_MATCH')),
    matched_name            VARCHAR(255),
    match_score             NUMERIC(5, 2),
    match_confidence_pct    NUMERIC(5, 2),
    notes                   TEXT,
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_raw_transactions_customer_date ON staging.raw_transactions(customer_id, txn_date_ph DESC);
CREATE INDEX IF NOT EXISTS idx_raw_transactions_branch       ON staging.raw_transactions(branch_code, txn_date_ph DESC);
CREATE INDEX IF NOT EXISTS idx_raw_transactions_amount       ON staging.raw_transactions(amount_php DESC) WHERE amount_php >= 500000;
CREATE INDEX IF NOT EXISTS idx_raw_customers_pep             ON staging.raw_customers(is_pep) WHERE is_pep = TRUE;
CREATE INDEX IF NOT EXISTS idx_raw_customers_risk_tier       ON staging.raw_customers(risk_tier);
CREATE INDEX IF NOT EXISTS idx_raw_customers_branch          ON staging.raw_customers(branch_code);
CREATE INDEX IF NOT EXISTS idx_raw_kyc_customer              ON staging.raw_kyc_documents(customer_id);
CREATE INDEX IF NOT EXISTS idx_raw_kyc_expiry                ON staging.raw_kyc_documents(expiry_date) WHERE expiry_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_raw_watchlist_source          ON staging.raw_watchlist_screening(watchlist_source, match_status);

-- Grants to aml_pipeline
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_transactions        TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_customers           TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_kyc_documents       TO aml_pipeline;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_watchlist_screening TO aml_pipeline;

-- Grants to airflow_amlc_user
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_transactions        TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_customers           TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_kyc_documents       TO airflow_amlc_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON staging.raw_watchlist_screening TO airflow_amlc_user;

-- Grants to metabase_amlc_user (read-only, staging is typically not exposed but included for completeness)
GRANT SELECT ON staging.raw_transactions        TO metabase_amlc_user;
GRANT SELECT ON staging.raw_customers           TO metabase_amlc_user;
GRANT SELECT ON staging.raw_kyc_documents       TO metabase_amlc_user;
GRANT SELECT ON staging.raw_watchlist_screening TO metabase_amlc_user;

\echo 'Staging tables created successfully'