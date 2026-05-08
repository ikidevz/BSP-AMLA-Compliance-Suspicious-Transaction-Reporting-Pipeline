# BSP/AMLA Compliance & Suspicious Transaction Reporting Pipeline

![img-url](https://tdhghaslnufgtzjybhhf.supabase.co/storage/v1/object/public/content/Data%20Engineering/bsp-aml-compliance-pipeline/archtectural_sketch.png)

## Overview

A production-grade Apache Airflow + dbt data pipeline for **Bank of Philippine Islands (BSP)** Anti-Money Laundering (AML) and Suspicious Transaction Reporting (STR) compliance automation.

**Regulation**: Republic Act 9160 (AMLA) | BSP Circular 706 | AMLC Circulars

### Key Capabilities

- **Covered Transaction Reporting (CTR)**: ₱500,000+ cash threshold detection per BSP Circular 706
- **Suspicious Transaction Reporting (STR)**: No amount threshold; 5 PH working-day filing deadline per RA 9160 Section 3(b-1)
- **AML Pattern Detection**:
  - Structuring (breaking up transactions to avoid CTR)
  - Layering (rapid in-out funds movement with minimal net position)
  - Dormancy (sudden account activity after prolonged inactivity)
  - Round-number transactions (possible smurfing indicator)
- **KYC Health Monitoring**: Document expiry tracking, refresh due dates per risk tier
- **Customer Risk Rating**: Integrated risk score (PEP, geography, KYC, watchlist, account status)
- **PII Data Masking**: RA 10173 compliance (Philippine Data Privacy Act)
- **Synthetic Data Generation**: Realistic banking scenarios with AML pattern injection

---

## Architecture

### Technology Stack

| Component          | Version | Purpose                             |
| ------------------ | ------- | ----------------------------------- |
| **Apache Airflow** | 3.2.1   | Workflow orchestration & scheduling |
| **dbt**            | 1.8.5   | Data transformation & lineage       |
| **PostgreSQL**     | 16      | Transactional & analytical database |
| **Metabase**       | v0.48.2 | BI dashboards & reporting           |
| **Docker**         | Latest  | Container orchestration             |

### Data Architecture (Medallion Pattern)

```
staging (Raw Ingestion)
    ↓ (dbt seed)
bronze (Validated Raw Data)
    ↓
silver (Business Logic & AML Detection)
    ├── int_ctr_candidates
    ├── int_str_candidates
    ├── int_structuring_detection
    ├── int_layering_detection
    ├── int_customer_risk_rating
    └── int_kyc_health
    ↓
gold (Compliance-Ready Analytics)
    ├── fct_covered_transactions
    ├── fct_suspicious_transactions
    ├── fct_customer_compliance
    ├── fct_branch_compliance_summary
    ├── dim_customers (SCD Type 2)
    ├── dim_branches
    └── dim_date
```

### DAGs

#### 1. **`aml_compliance_pipeline`** (Daily, Mon-Sat @ 2:00 AM PHT)

Generates synthetic data → Transforms with dbt → Produces CTR/STR candidates

```
[generate_transactions] ────┐
[generate_customers]    ────├──> [dbt_seed] → [dbt_run] → [dbt_test] → [mark_complete]
[generate_kyc_documents]───┘
```

**Schedule**: `0 2 * * 1-6` (UTC+8: 18:00 UTC previous day)

**Tasks**:

- `generate_transactions`: 10,000 synthetic txns/day (20% AML pattern injection)
- `generate_customers`: 500 synthetic customers
- `generate_kyc_documents`: KYC docs per customer
- `dbt_seed`: Load reference tables
- `dbt_run`: Run all bronze → silver → gold models
- `dbt_test`: Data quality tests
- `mark_pipeline_complete`: Log successful completion

#### 2. **`aml_monthly_report`** (Monthly, 1st of month @ 6:00 AM PHT)

Generates AMLC ERS formatted compliance reports

```
[export_ctr_report] ────┐
                   ────┼──> [generate_summary_report]
[export_str_report] ────┘
```

**Schedule**: `0 6 1 * *` (6:00 AM on 1st)

**Tasks**:

- `export_ctr_report`: Query gold.fct_covered_transactions, export CSV
- `export_str_report`: Query gold.fct_suspicious_transactions, export CSV
- `generate_summary_report`: Summary with metadata

---

## Quick Start

### Prerequisites

- Docker & Docker Compose installed
- 4GB+ RAM for containers
- Port availability: 8080 (Airflow UI), 5432 (PostgreSQL), 3000 (Metabase)

### Setup

```bash
# Clone/extract repository
cd bsp-aml-compliance-pipeline

# Copy environment template
cp .env.example .env
# Edit .env with your values (optional; defaults included)

# Start all services
docker-compose up -d

# Initialize Airflow database
docker-compose exec airflow_scheduler airflow db init

# Create Airflow admin user
docker-compose exec airflow_scheduler airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password admin

# Wait for services to be healthy (~2 minutes)
docker-compose ps

# View logs
docker-compose logs -f airflow_scheduler
docker-compose logs -f postgres
```

### Access

- **Airflow UI**: http://localhost:8080 (admin/admin)
- **Metabase**: http://localhost:3000 (setup wizard)
- **PostgreSQL**: localhost:5432 (aml_pipeline/aml_pipeline_pwd)

### Trigger DAG Manually

```bash
# Trigger daily pipeline
docker-compose exec airflow_scheduler airflow dags trigger aml_compliance_pipeline

# Trigger monthly report
docker-compose exec airflow_scheduler airflow dags trigger aml_monthly_report

# View execution
# Navigate to http://localhost:8080 → DAGs → Select DAG → Graph
```

---

## Database Schema

### Staging Layer (Raw Ingestion)

```sql
staging.raw_transactions
staging.raw_customers
staging.raw_kyc_documents
staging.raw_watchlist_screening
```

### Reference Data (Seeds)

Loaded via dbt seed from CSV files:

```
seeds/
├── ph_branches.csv            -- Philippine branch master
├── fatf_jurisdictions.csv     -- FATF blacklist/greylist
├── aml_risk_weights.csv       -- Risk scoring weights
├── ph_non_working_days.csv    -- PH holidays for deadline calculations
└── str_indicators_ref.csv     -- STR indicator definitions
```

### Bronze Layer (Validated Raw)

- `bronze.stg_transactions`
- `bronze.stg_customers`
- `bronze.stg_kyc_documents`
- `bronze.stg_watchlist`

### Silver Layer (Business Logic)

**AML Detection Models**:

- `silver.int_ctr_candidates`: CTR-eligible transactions
- `silver.int_str_candidates`: STR detection signals (all indicators)
- `silver.int_structuring_detection`: 7-day rolling window pattern detection
- `silver.int_layering_detection`: 48-hour in-out movement analysis
- `silver.int_customer_risk_rating`: Integrated risk score (0-100)
- `silver.int_kyc_health`: KYC completeness & freshness tracking

### Gold Layer (Analytics-Ready)

**Fact Tables**:

- `gold.fct_covered_transactions`: CTR filing facts (1-day filing deadline)
- `gold.fct_suspicious_transactions`: STR filing facts (5 working-day deadline)
- `gold.fct_customer_compliance`: Customer compliance summary
- `gold.fct_branch_compliance_summary`: Branch-level KPIs

**Dimension Tables**:

- `gold.dim_customers`: SCD Type 2 customer master with risk ratings
- `gold.dim_branches`: Philippine branch reference
- `gold.dim_date`: Philippine fiscal calendar with working day flags

---

## AML Pattern Detection

### Structuring Detection (`int_structuring_detection`)

**Pattern**: Multiple sub-threshold transactions within 7 days to avoid ₱500,000 CTR threshold

**Logic**:

```sql
WHERE txn_count_7d >= 3
  AND txn_sum_7d >= 450000
  AND amount_php < 490000
```

**Risk Score**: 70 (base)

### Layering Detection (`int_layering_detection`)

**Pattern**: Rapid funds in-out movement with minimal net position (48-hour window)

**Logic**:

```sql
WHERE amount_in_48h > 50000
  AND amount_out_48h > 50000
  AND net_position_pct < 10%
```

**Risk Score**: 65 (base)

### Covered Transaction Detection (`int_ctr_candidates`)

**Pattern 1**: Single cash transaction ≥ ₱500,000

**Pattern 2**: Related daily transactions (same customer, banking day) totaling ≥ ₱500,000

**Pattern 3**: FOREX transactions ≥ USD 10,000 equivalent

### STR Signal Aggregation (`int_str_candidates`)

Combines all AML indicators:

- Structuring patterns
- Layering patterns
- FATF jurisdiction matches
- PEP transactions (₱50,000+)
- Round-number transactions
- KYC deficiencies
- Watchlist matches
- Account dormancy anomalies

---

## Configuration

### Environment Variables (`.env`)

```bash
# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres_admin_pwd

# Airflow
AIRFLOW__CORE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow_amlc_user:airflow_pwd@postgres:5432/airflow_db
AIRFLOW__CORE__EXECUTOR=LocalExecutor

# dbt / AML Pipeline
DBT_POSTGRES_USER=aml_pipeline
DBT_POSTGRES_PASSWORD=aml_pipeline_pwd
DBT_POSTGRES_HOST=postgres
DBT_POSTGRES_PORT=5432

# Data Generation
SYNTHETIC_DATA_VOLUME_TXN=10000           # Transactions per run
SYNTHETIC_DATA_AML_INJECTION_PCT=0.20     # 20% with AML patterns
SEED_VALUE=42                             # Reproducibility

# Metabase
MB_DB_HOST=postgres
MB_DB_USER=metabase_amlc_user
MB_DB_PASS=metabase_pwd
```

### dbt Variables

In `dbt/dbt_project.yml`:

```yaml
vars:
  ctr_php_threshold: 500000 # CTR single txn threshold
  ctr_forex_threshold: 10000 # CTR FOREX threshold (USD)
  str_max_net_position_pct: 10 # Layering threshold
  structuring_txn_count: 3 # Min txns in 7-day window
  structuring_sum_threshold: 450000 # Min sum for structuring pattern
```

---

## Data Quality Tests

dbt tests located in `dbt/tests/`:

```sql
-- Primary key uniqueness
tests/fct_covered_transactions_pkey.sql
tests/fct_suspicious_transactions_pkey.sql

-- Foreign key referential integrity
tests/dim_customers_branch_code_fk.sql

-- Data completeness
tests/dim_customers_not_null.sql

-- Business logic validation
tests/fct_covered_transactions_threshold.sql  -- Verify amount >= ₱500k
```

Run tests:

```bash
docker-compose exec airflow_scheduler dbt test --project-dir /opt/airflow/dbt
```

---

## PII Masking & Compliance

### Data Privacy (RA 10173)

All customer PII masked in `gold.dim_customers`:

- Customer Name: "A\*\*\*N" (first & last letter only)
- SSS Number: "\*\*\*XXXX" (last 4 digits)
- TIN Number: "\*\*\*XXXX" (last 4 digits)
- Full data retained in `staging`/`bronze` (access restricted to aml_pipeline role)

### Row-Level Security

PostgreSQL RLS policies (init-script `06_row_level_security.sql`):

- `metabase_amlc_user`: Sees only gold schema (masked data)
- `audit_logger`: Can only INSERT audit logs
- Auditors: Can view all layers with explicit role grants

---

## Monitoring & Troubleshooting

### Check DAG Status

```bash
# List all DAGs
docker-compose exec airflow_scheduler airflow dags list

# List DAG runs
docker-compose exec airflow_scheduler airflow dags list-runs -d aml_compliance_pipeline

# Trigger & watch
docker-compose exec airflow_scheduler airflow dags trigger aml_compliance_pipeline
docker-compose logs -f airflow_scheduler | grep aml_compliance_pipeline
```

### Database Health

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres -d aml_compliance_db

# Check table sizes
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables WHERE schemaname IN ('staging', 'bronze', 'silver', 'gold')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

# Check recent CTR/STR generation
SELECT COUNT(*), creation_date FROM gold.fct_covered_transactions GROUP BY creation_date;
```

### dbt Lineage & Documentation

```bash
# Generate dbt docs
docker-compose exec airflow_scheduler dbt docs generate --project-dir /opt/airflow/dbt

# Serve docs (requires additional setup)
# dbt docs serve --port 8001
```

### Common Issues

| Issue                                             | Solution                                                                           |
| ------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Airflow scheduler not picking up DAG changes      | Restart scheduler: `docker-compose restart airflow_scheduler`                      |
| dbt models failing with "relation does not exist" | Ensure `dbt seed` task completed first; check staging tables exist                 |
| CTR/STR reporting shows 0 rows                    | Check synthetic data generation succeeded; verify `amount_php > 0` in transactions |
| Metabase connection fails                         | Verify `postgres` service is healthy; check `.env` credentials                     |
| Performance slow on large datasets                | Add indexes: run `init-scripts/05_indexes.sql` manually                            |

---

## File Structure

```
bsp-aml-compliance-pipeline/
├── dags/                              # Airflow DAGs
│   ├── aml_compliance_pipeline.py     # Daily pipeline (Mon-Sat)
│   ├── aml_monthly_report.py          # Monthly reports (1st of month)
│   └── src/
│       ├── db.py                      # Database connection pool
│       ├── logger.py                  # JSON structured logging
│       ├── generate_transactions.py   # Synthetic txn generation
│       ├── generate_customers.py      # Synthetic customer generation
│       └── generate_kyc.py            # KYC document generation
│
├── dbt/                               # dbt project
│   ├── models/
│   │   ├── staging/                   # Bronze layer (raw validation)
│   │   │   ├── stg_transactions.sql
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_kyc_documents.sql
│   │   │   ├── stg_watchlist.sql
│   │   │   ├── schema.yml
│   │   │   ├── sources.yml
│   │   │   └── tests/
│   │   │
│   │   ├── intermediate/              # Silver layer (AML logic)
│   │   │   ├── int_ctr_candidates.sql
│   │   │   ├── int_str_candidates.sql
│   │   │   ├── int_structuring_detection.sql
│   │   │   ├── int_layering_detection.sql
│   │   │   ├── int_customer_risk_rating.sql
│   │   │   └── int_kyc_health.sql
│   │   │
│   │   └── marts/                     # Gold layer (analytics)
│   │       ├── fct_covered_transactions.sql
│   │       ├── fct_suspicious_transactions.sql
│   │       ├── fct_customer_compliance.sql
│   │       ├── fct_branch_compliance_summary.sql
│   │       ├── dim_customers.sql
│   │       ├── dim_branches.sql
│   │       └── dim_date.sql
│   │
│   ├── macros/                        # dbt macros
│   ├── tests/                         # dbt data quality tests
│   ├── seeds/
│   │   ├── ph_branches.csv
│   │   ├── fatf_jurisdictions.csv
│   │   ├── aml_risk_weights.csv
│   │   ├── ph_non_working_days.csv
│   │   └── str_indicators_ref.csv
│   │
│   ├── dbt_project.yml
│   └── profiles.yml
│
├── init-scripts/                      # PostgreSQL initialization
│   ├── 00_create_databases.sql
│   ├── 01_create_schemas.sql
│   ├── 02_create_roles.sql
│   ├── 03_staging_tables.sql
│   ├── 04_seed_tables.sql
│   ├── 05_indexes.sql
│   └── 06_row_level_security.sql
│
├── config/                            # Configuration
│   ├── metabase/
│   ├── pgadmin/
│   └── ...
│
├── reports/                           # Output directory for CTR/STR reports
│
├── docker-compose.yml
├── Dockerfile.airflow
├── .env.example
├── requirements.txt
└── README.md
```

---

## Production Deployment

### Pre-Deployment Checklist

- [ ] Update `.env` with production secrets (PostgreSQL, Airflow, Metabase passwords)
- [ ] Configure Airflow email alerts (SMTP settings)
- [ ] Set up PostgreSQL backups (daily, retained 30 days)
- [ ] Configure log aggregation (CloudWatch, DataDog, etc.)
- [ ] Enable dbt artifacts upload to data catalog (dbt Cloud optional)
- [ ] Set up monitoring (Prometheus + Grafana or equivalent)
- [ ] Test disaster recovery (restore from backup)
- [ ] Compliance audit trail (audit schema logging)
- [ ] PII handling documentation (RA 10173)
- [ ] AMLC reporting SLA enforcement (CTR: 1 day, STR: 5 working days)

### Deployment on Kubernetes

Adapt `docker-compose.yml` for Helm/Kustomize:

```bash
# Build images for registry
docker build -f Dockerfile.airflow -t myregistry/airflow:latest .
docker push myregistry/airflow:latest

# Deploy Helm chart (example)
helm install bsp-aml-pipeline ./helm-charts/airflow \
  --namespace aml \
  --values production-values.yaml
```

---

## Contributing

### Adding New AML Indicators

1. Create intermediate model: `dbt/models/intermediate/int_your_indicator.sql`
2. Add test: `dbt/tests/int_your_indicator_test.sql`
3. Update `int_str_candidates` to include new signal
4. Document in README

### Testing Changes

```bash
# Parse dbt models
dbt parse --project-dir dbt

# Validate SQL
dbt compile --project-dir dbt

# Run dbt tests
dbt test --project-dir dbt

# Run specific model
dbt run --project-dir dbt --select int_your_indicator
```

---

## Legal & Compliance

**Jurisdiction**: Philippines

**Regulations**:

- **RA 9160**: Anti-Money Laundering Act (as amended)
- **RA 10927**: Enhanced AMLC Powers
- **BSP Circular 706**: Manual of Regulations for Banks (AML/CTF)
- **RA 10173**: Data Privacy Act (PII masking requirements)
- **AMLC Circulars**: Money Services Business rules, Filing requirements

**Data Retention**: 10 years minimum (per RA 9160 Section 12)

**Reporting**:

- CTR: 1-day filing deadline
- STR: 5 Philippine working-day filing deadline
- Both filed to: AMLC (Anti-Money Laundering Council)

---

## Support & Maintenance

**Documentation**: See inline SQL comments for data lineage

**Issue Tracker**: Create issues for bugs, feature requests

**Maintenance Windows**: Coordinate backup/maintenance outside 1-6 AM PHT

**SLA**: CTR/STR reports generated daily; monthly summary on 1st

---

## License

[Specify your license - e.g., MIT, Proprietary, etc.]

---

## Contact

For questions, issues, or compliance concerns:

- Email: aml-compliance-team@bankname.com.ph
- Slack: #aml-pipeline-support
- JIRA: [Project key]

---

**Last Updated**: May 2026
**Version**: 1.0.0
