-- models/marts/fct_covered_transactions.sql
-- Fact Table: fct_covered_transactions
-- Covered Transaction Report (CTR) facts per BSP Circular 706
-- One row per CTR-eligible transaction (PHP 500,000+ cash threshold)


{{ config(
    materialized='table',
    schema='gold',
    post_hook=[
        "CREATE INDEX IF NOT EXISTS idx_fct_ctr_customer       ON {{ this }}(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_fct_ctr_date           ON {{ this }}(txn_date_ph DESC)",
        "CREATE INDEX IF NOT EXISTS idx_fct_ctr_filing_status  ON {{ this }}(filing_status) WHERE filing_status != 'FILED'",
        "CREATE INDEX IF NOT EXISTS idx_fct_ctr_branch         ON {{ this }}(branch_code)",
        "CREATE INDEX IF NOT EXISTS idx_fct_ctr_amount         ON {{ this }}(amount_php DESC) WHERE amount_php >= 500000"
    ]
) }}

WITH ctr_candidates AS (
    SELECT * FROM {{ ref('int_ctr_candidates') }}
),

-- Note: customers CTE removed — no customer columns are selected in this fact table.
-- Customer attributes live in dim_customers; join there at query time.

branches AS (
    SELECT * FROM {{ ref('dim_branches') }}
),

date_dim AS (
    SELECT * FROM {{ ref('dim_date') }}
),

ctr_enriched AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['cc.txn_id', 'cc.ctr_type']) }}
                                                        AS ctr_id,
        cc.txn_id,
        cc.customer_id,

        -- FK to dim_date
        dmd.date_id                                     AS txn_date_id,
        cc.txn_date_ph,

        -- FK to dim_branches (using ref not source for lineage)
        b.branch_code,

        cc.amount_php,
        cc.transaction_direction,
        cc.ctr_type,
        cc.txn_channel,

        -- BSP Circular 706: CTR must be filed within 1 PH working day
        {{ ph_working_day_deadline('cc.txn_date_ph::DATE', 1) }}::DATE
                                                        AS filing_deadline,

        'PENDING'::VARCHAR                              AS filing_status,
        NULL::DATE                                      AS filing_date,
        NULL::VARCHAR                                   AS amlc_ers_reference,

        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'   AS dbt_loaded_at

    FROM ctr_candidates cc
    LEFT JOIN branches b
        ON cc.branch_code = b.branch_code
    LEFT JOIN date_dim dmd
        ON cc.txn_date_ph::DATE = dmd.calendar_date
)

SELECT * FROM ctr_enriched