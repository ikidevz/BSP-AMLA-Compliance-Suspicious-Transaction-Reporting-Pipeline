# BSP/AMLA Compliance & Suspicious Transaction Reporting Pipeline

![Architecture Sketch](https://tdhghaslnufgtzjybhhf.supabase.co/storage/v1/object/public/content/Data%20Engineering/bsp-aml-compliance-pipeline/archtectural_sketch.png)

## Overview

A production-grade Apache Airflow + dbt data pipeline for **BSP (Bangko Sentral ng Pilipinas)** Anti-Money Laundering (AML) compliance automation. It generates synthetic banking transactions, detects AML patterns, and produces AMLC-ready Covered Transaction Reports (CTR) and Suspicious Transaction Reports (STR).

**Governing Regulations**: RA 9160 (AMLA) · BSP Circular 706 · RA 10173 (Data Privacy Act) · AMLC Circulars

---

## Key Capabilities

- **Covered Transaction Reporting (CTR)** — ₱500,000+ cash threshold detection per BSP Circular 706; 1-day filing deadline
- **Suspicious Transaction Reporting (STR)** — No amount threshold; 5 PH working-day filing deadline per RA 9160 §3(b-1)
- **AML Pattern Detection**:
  - Structuring — sub-threshold transactions within a 7-day window to avoid CTR
  - Layering — rapid in-out funds movement with minimal net position (48-hour window)
  - Dormancy — sudden account activity after prolonged inactivity
  - Round-number / smurfing indicators
- **KYC Health Monitoring** — Document expiry tracking and refresh due dates per risk tier
- **Customer Risk Rating** — Composite score (PEP status, geography, KYC completeness, watchlist, account status)
- **PII Data Masking** — RA 10173 compliance; full data retained only in restricted staging/bronze layers
- **Synthetic Data Generation** — Realistic banking scenarios with configurable AML pattern injection

---

## Technology Stack

| Component      | Version | Purpose                             |
| -------------- | ------- | ----------------------------------- |
| Apache Airflow | 3.2.1   | Workflow orchestration & scheduling |
| dbt            | 1.8.5   | Data transformation & lineage       |
| PostgreSQL     | 16      | Transactional & analytical database |
| Metabase       | Latest  | BI dashboards & reporting           |
| Redis          | 7.2     | Celery task broker                  |
| Docker Compose | —       | Local service orchestration         |

---

## Data Architecture (Medallion Pattern)

```
staging      Raw ingestion (Python generators → PostgreSQL)
    ↓
bronze       Validated raw data (dbt staging models)
    ├── stg_transactions
    ├── stg_customers
    ├── stg_kyc_documents
    └── stg_watchlist
    ↓
silver       Business logic & AML detection (dbt intermediate models)
    ├── int_ctr_candidates
    ├── int_str_candidates
    ├── int_structuring_detection
    ├── int_layering_detection
    ├── int_customer_risk_rating
    └── int_kyc_health
    ↓
gold         Compliance-ready analytics (dbt marts)
    ├── fct_covered_transactions
    ├── fct_suspicious_transactions
    ├── fct_customer_compliance
    ├── fct_branch_compliance_summary
    ├── dim_customers (SCD Type 2, PII-masked)
    ├── dim_branches
    └── dim_date
```

---

## DAGs

### `aml_compliance_pipeline` — Daily (Mon–Sat, 2:00 AM PHT)

Generates synthetic data → runs dbt transformations → produces CTR/STR candidates.

```
[generate_customers] ──┐
[generate_transactions] ─┼──> [dbt_init] → [dbt_seed] → [dbt_run] → [dbt_test] → [mark_complete]
[generate_kyc_documents] ┘
```

**Cron**: `0 2 * * 1-6` (PHT = UTC+8; equivalent to 18:00 UTC previous day)

| Task                     | Description                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------- |
| `generate_customers`     | Generates 500 synthetic customers                                                  |
| `generate_transactions`  | Generates 5,000 synthetic transactions (20% AML patterns by default)               |
| `generate_kyc_documents` | Generates KYC documents per customer                                               |
| `dbt_init`               | Installs dbt package dependencies (`dbt deps`)                                     |
| `dbt_seed`               | Loads reference CSVs (branches, FATF list, risk weights, holidays, STR indicators) |
| `dbt_run`                | Runs all bronze → silver → gold models                                             |
| `dbt_test`               | Runs dbt data quality tests                                                        |
| `mark_pipeline_complete` | Logs successful run with timestamp                                                 |

---

### `aml_monthly_report` — Monthly (1st of month, 6:00 AM PHT)

Exports AMLC ERS-formatted compliance reports from the gold layer.

```
[export_ctr_report] ─┐
                      ├──> [generate_summary_report]
[export_str_report] ─┘
```

**Cron**: `0 6 1 * *`

| Task                      | Description                                             |
| ------------------------- | ------------------------------------------------------- |
| `export_ctr_report`       | Queries `gold.fct_covered_transactions`, exports CSV    |
| `export_str_report`       | Queries `gold.fct_suspicious_transactions`, exports CSV |
| `generate_summary_report` | Prints report summary with date and output paths        |

Reports are saved to `/reports/{year}/{month}/`.

---

## Quick Start

### Prerequisites

Before starting, ensure you have:

- **Docker** and **Docker Compose** installed and running
- At least **4 GB RAM** available for containers
- The following ports free: `8080` (Airflow UI), `5432` (PostgreSQL), `3000` (Metabase), `5050` (pgAdmin)

---

### Step 1 — Clone the repository

```bash
git clone <your-repo-url>
cd bsp-aml-compliance-pipeline
```

---

### Step 2 — Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in your values. All fields have working defaults for local development — the minimum you should change are the passwords.

Key variables:

```bash
# PostgreSQL (Airflow metadata DB)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=airflow_db

# Airflow
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://postgres:your_secure_password@postgres:5432/airflow_db
AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://postgres:your_secure_password@postgres:5432/airflow_db
AIRFLOW__CELERY__BROKER_URL=redis://:@redis:6379/0
FERNET_KEY=<generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())">

# AML pipeline DB (separate from Airflow metadata)
DBT_POSTGRES_HOST=postgres
DBT_POSTGRES_PORT=5432
DBT_POSTGRES_DBNAME=aml_compliance_db
DBT_POSTGRES_USER=aml_pipeline
DBT_POSTGRES_PASSWORD=aml_pipeline_pwd

# Data generation
SYNTHETIC_DATA_VOLUME_TXN=5000
SYNTHETIC_DATA_AML_INJECTION_PCT=0.20

# Metabase
METABASE_PORT=3000
MB_DB_DBNAME=metabase_db
MB_DB_USER=metabase_user
MB_DB_PASS=metabase_password

# pgAdmin
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=admin
```

Generate a Fernet key if you don't have one:

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

---

### Step 3 — Set the Airflow UID (Linux only)

On Linux, Airflow needs the correct user ID to avoid file permission issues:

```bash
echo "AIRFLOW_UID=$(id -u)" >> .env
```

On macOS/Windows, skip this step.

---

### Step 4 — Build and start all services

```bash
docker compose up -d --build
```

This will:

- Build the custom Airflow image (`Dockerfile.airflow`) with required Python packages
- Start PostgreSQL, Redis, Metabase, pgAdmin, and all Airflow components
- Run `airflow-init` automatically to migrate the database and create the default admin user

The first startup takes **3–5 minutes**. Wait for all services to become healthy:

```bash
docker compose ps
```

All services should show `healthy` or `running`. If `airflow-init` exits with code `0`, that is expected — it runs once and stops.

---

### Step 5 — Verify services are up

```bash
# Check Airflow API health
curl http://localhost:8080/api/v2/monitor/health

# Check PostgreSQL
docker compose exec postgres pg_isready -U postgres
```

---

### Step 6 — Access the UIs

| Service    | URL                   | Default credentials            |
| ---------- | --------------------- | ------------------------------ |
| Airflow UI | http://localhost:8080 | `airflow` / `airflow`          |
| Metabase   | http://localhost:3000 | Setup wizard on first launch   |
| pgAdmin    | http://localhost:5050 | From your `.env` PGADMIN vars  |
| PostgreSQL | `localhost:5432`      | From your `.env` POSTGRES vars |

> **Security note**: Change the default Airflow credentials immediately in production. Set `_AIRFLOW_WWW_USER_USERNAME` and `_AIRFLOW_WWW_USER_PASSWORD` in your `.env`.

---

### Step 7 — Enable and trigger the DAGs

By default, DAGs are paused on creation. Enable them from the Airflow UI, or via the CLI:

```bash
# Enable DAGs
docker compose exec airflow-scheduler airflow dags unpause aml_compliance_pipeline
docker compose exec airflow-scheduler airflow dags unpause aml_monthly_report

# Trigger manually (runs immediately without waiting for schedule)
docker compose exec airflow-scheduler airflow dags trigger aml_compliance_pipeline
docker compose exec airflow-scheduler airflow dags trigger aml_monthly_report
```

Then open http://localhost:8080, navigate to the DAG, and click the **Graph** tab to watch task execution in real time.

---

## Configuration Reference

### Environment Variables

| Variable                           | Default             | Description                                |
| ---------------------------------- | ------------------- | ------------------------------------------ |
| `SYNTHETIC_DATA_VOLUME_TXN`        | `5000`              | Transactions generated per daily run       |
| `SYNTHETIC_DATA_AML_INJECTION_PCT` | `0.20`              | Fraction of transactions with AML patterns |
| `SYNTHETIC_DATA_VOLUME_CUSTOMERS`  | `500`               | Customers generated per daily run          |
| `DBT_POSTGRES_HOST`                | `postgres`          | dbt/AML pipeline DB host                   |
| `DBT_POSTGRES_PORT`                | `5432`              | dbt/AML pipeline DB port                   |
| `DBT_POSTGRES_DBNAME`              | `aml_compliance_db` | dbt/AML pipeline DB name                   |
| `METABASE_PORT`                    | `3000`              | Metabase exposed port                      |

### dbt Variables (`dbt/dbt_project.yml`)

```yaml
vars:
  ctr_php_threshold: 500000 # CTR single-transaction threshold (₱)
  ctr_forex_threshold: 10000 # CTR FOREX threshold (USD equivalent)
  str_max_net_position_pct: 10 # Layering detection: max net position %
  structuring_txn_count: 3 # Min transactions in 7-day window for structuring
  structuring_sum_threshold: 450000 # Min sum for structuring pattern (₱)
```

---

## AML Detection Logic

### Structuring (`int_structuring_detection`)

Detects multiple sub-threshold transactions in a 7-day rolling window intended to avoid the ₱500,000 CTR threshold.

```sql
WHERE txn_count_7d >= 3
  AND txn_sum_7d >= 450000
  AND amount_php < 490000
```

Base risk score: **70**

---

### Layering (`int_layering_detection`)

Detects rapid in-out fund movement with minimal net position in a 48-hour window.

```sql
WHERE amount_in_48h > 50000
  AND amount_out_48h > 50000
  AND net_position_pct < 10
```

Base risk score: **65**

---

### Covered Transactions (`int_ctr_candidates`)

Three CTR trigger patterns:

- **Pattern 1** — Single cash transaction ≥ ₱500,000
- **Pattern 2** — Related transactions on the same banking day totaling ≥ ₱500,000
- **Pattern 3** — FOREX transaction ≥ USD 10,000 equivalent

---

### STR Signal Aggregation (`int_str_candidates`)

Combines all AML indicators into a composite risk score:

- Structuring and layering patterns
- FATF jurisdiction matches
- PEP transactions ≥ ₱50,000
- Round-number / smurfing indicators
- KYC deficiencies
- Watchlist matches
- Account dormancy anomalies

---

## Database Schema

### Staging (Raw Ingestion)

```
staging.raw_transactions
staging.raw_customers
staging.raw_kyc_documents
staging.raw_watchlist_screening
```

### Reference Seeds

Loaded via `dbt seed`:

```
seeds/
├── ph_branches.csv            Philippine branch master
├── fatf_jurisdictions.csv     FATF blacklist/greylist
├── aml_risk_weights.csv       Risk scoring weights
├── ph_non_working_days.csv    PH public holidays (for deadline calculation)
└── str_indicators_ref.csv     STR indicator definitions
```

### Bronze Layer

```
bronze.stg_transactions
bronze.stg_customers
bronze.stg_kyc_documents
bronze.stg_watchlist
```

### Silver Layer

```
silver.int_ctr_candidates
silver.int_str_candidates
silver.int_structuring_detection
silver.int_layering_detection
silver.int_customer_risk_rating
silver.int_kyc_health
```

### Gold Layer

**Facts**

```
gold.fct_covered_transactions       CTR facts with 1-day filing deadline
gold.fct_suspicious_transactions    STR facts with 5 working-day deadline
gold.fct_customer_compliance        Customer compliance summary
gold.fct_branch_compliance_summary  Branch-level KPIs
```

**Dimensions**

```
gold.dim_customers    SCD Type 2; PII masked per RA 10173
gold.dim_branches     Philippine branch reference
gold.dim_date         PH fiscal calendar with working-day flags
```

---

## PII Masking & Data Privacy (RA 10173)

Customer PII is masked in `gold.dim_customers`:

| Field         | Masked Format            | Example   |
| ------------- | ------------------------ | --------- |
| Customer Name | First & last letter only | `A***N`   |
| SSS Number    | Last 4 digits            | `***1234` |
| TIN Number    | Last 4 digits            | `***5678` |

Full unmasked data remains in `staging` and `bronze` layers, accessible only to the `aml_pipeline` database role.

### Row-Level Security

PostgreSQL RLS policies (applied by `init-scripts/06_row_level_security.sql`):

| Role                 | Access                               |
| -------------------- | ------------------------------------ |
| `metabase_amlc_user` | Gold schema only (masked data)       |
| `audit_logger`       | INSERT to audit logs only            |
| Auditor roles        | All layers (explicit grant required) |

---

## Monitoring & Troubleshooting

### Check DAG Status

```bash
# List all DAGs
docker compose exec airflow-scheduler airflow dags list

# List runs for a specific DAG
docker compose exec airflow-scheduler airflow dags list-runs -d aml_compliance_pipeline

# Check task states for a specific run
docker compose exec airflow-scheduler airflow tasks states-for-dag-run aml_compliance_pipeline <run_id>

# Stream scheduler logs
docker compose logs -f airflow-scheduler
```

### Database Health

```bash
# Connect to PostgreSQL
docker compose exec postgres psql -U postgres -d aml_compliance_db

# Check table sizes across all layers
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS size
FROM pg_tables
WHERE schemaname IN ('staging', 'bronze', 'silver', 'gold')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;

# Verify CTR generation
SELECT DATE(creation_date), COUNT(*)
FROM gold.fct_covered_transactions
GROUP BY 1
ORDER BY 1 DESC;

# Verify STR generation
SELECT DATE(str_determination_ts), COUNT(*)
FROM gold.fct_suspicious_transactions
GROUP BY 1
ORDER BY 1 DESC;
```

### dbt Docs

```bash
# Generate documentation
docker compose exec airflow-scheduler \
  dbt docs generate --profiles-dir /opt/airflow/dbt --project-dir /opt/airflow/dbt

# Serve locally (run from host after copying artifacts)
dbt docs serve --port 8001
```

### Common Issues

| Symptom                                  | Likely Cause                                          | Fix                                                                                   |
| ---------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------- |
| DAG not appearing in UI                  | File syntax error or import failure                   | Run `docker compose logs airflow-dag-processor` to see parsing errors                 |
| `airflow-init` exits with non-zero code  | Missing env vars or DB connection failure             | Check `.env` values; ensure `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` is correct          |
| dbt fails with "relation does not exist" | `dbt_seed` didn't complete, or staging tables missing | Check the `dbt_seed` task logs; re-run `airflow dags trigger aml_compliance_pipeline` |
| CTR/STR reports show 0 rows              | Data generation task failed                           | Check `generate_transactions` task logs; verify `staging.raw_transactions` has rows   |
| Metabase can't connect to PostgreSQL     | Wrong credentials or DB not yet created               | Verify `MB_DB_*` vars in `.env`; ensure init scripts ran successfully                 |
| Slow performance on large datasets       | Missing indexes                                       | Run `init-scripts/05_indexes.sql` manually via psql                                   |
| Airflow workers not picking up tasks     | Redis or worker unhealthy                             | Run `docker compose ps` and restart unhealthy containers                              |

---

## Project Structure

```
bsp-aml-compliance-pipeline/
├── dags/
│   ├── aml_compliance_pipeline.py     Daily pipeline (Mon-Sat)
│   ├── aml_monthly_report.py          Monthly AMLC reports
│   └── src/
│       ├── utils/db.py                Database connection pool
│       ├── logger.py                  JSON structured logging
│       ├── generate_transactions.py   Synthetic transaction generator
│       ├── generate_customers.py      Synthetic customer generator
│       └── generate_kyc.py            KYC document generator
│
├── dbt/
│   ├── models/
│   │   ├── staging/                   Bronze layer (raw validation)
│   │   │   ├── stg_transactions.sql
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_kyc_documents.sql
│   │   │   ├── stg_watchlist.sql
│   │   │   ├── schema.yml
│   │   │   └── sources.yml
│   │   ├── intermediate/              Silver layer (AML detection logic)
│   │   │   ├── int_ctr_candidates.sql
│   │   │   ├── int_str_candidates.sql
│   │   │   ├── int_structuring_detection.sql
│   │   │   ├── int_layering_detection.sql
│   │   │   ├── int_customer_risk_rating.sql
│   │   │   └── int_kyc_health.sql
│   │   └── marts/                     Gold layer (analytics-ready)
│   │       ├── fct_covered_transactions.sql
│   │       ├── fct_suspicious_transactions.sql
│   │       ├── fct_customer_compliance.sql
│   │       ├── fct_branch_compliance_summary.sql
│   │       ├── dim_customers.sql
│   │       ├── dim_branches.sql
│   │       └── dim_date.sql
│   ├── seeds/
│   │   ├── ph_branches.csv
│   │   ├── fatf_jurisdictions.csv
│   │   ├── aml_risk_weights.csv
│   │   ├── ph_non_working_days.csv
│   │   └── str_indicators_ref.csv
│   ├── macros/
│   ├── tests/
│   ├── dbt_project.yml
│   └── profiles.yml
│
├── init-scripts/                      PostgreSQL initialization (runs on first DB start)
│   ├── 00_create_databases.sql
│   ├── 01_create_schemas.sql
│   ├── 02_create_roles.sql
│   ├── 03_staging_tables.sql
│   ├── 04_seed_tables.sql
│   ├── 05_indexes.sql
│   └── 06_row_level_security.sql
│
├── config/
│   ├── metabase/setup.sh              Auto-configures Metabase on first start
│   └── pgadmin/                       pgAdmin server connection config
│
├── reports/                           Output directory for CTR/STR CSV exports
│
├── docker-compose.yml
├── Dockerfile.airflow
├── requirements.txt
├── .env.example
└── README.md
```

---

## Contributing

### Adding a New AML Indicator

1. Create the intermediate model: `dbt/models/intermediate/int_your_indicator.sql`
2. Add a dbt test: `dbt/tests/int_your_indicator_test.sql`
3. Reference the new signal in `int_str_candidates.sql`
4. Update the `str_indicators_ref.csv` seed if adding a new indicator code
5. Document the pattern and SQL logic in this README

### Testing dbt Changes Locally

```bash
# Validate SQL without running
docker compose exec airflow-scheduler \
  dbt compile --profiles-dir /opt/airflow/dbt --project-dir /opt/airflow/dbt

# Run a specific model only
docker compose exec airflow-scheduler \
  dbt run --profiles-dir /opt/airflow/dbt --project-dir /opt/airflow/dbt \
  --select int_your_indicator

# Run all tests
docker compose exec airflow-scheduler \
  dbt test --profiles-dir /opt/airflow/dbt --project-dir /opt/airflow/dbt
```

---

## Production Deployment

### Pre-Deployment Checklist

- [ ] Replace all default passwords in `.env` with secrets manager values
- [ ] Generate a strong `FERNET_KEY` and `AIRFLOW__API_AUTH__JWT_SECRET`
- [ ] Configure Airflow SMTP settings for email alerts on failure
- [ ] Set up automated PostgreSQL backups (daily, 30-day retention minimum)
- [ ] Enable log aggregation (CloudWatch, Datadog, or equivalent)
- [ ] Apply `init-scripts/05_indexes.sql` on the production DB before first load
- [ ] Confirm RLS policies are active (`init-scripts/06_row_level_security.sql`)
- [ ] Verify CTR 1-day and STR 5 working-day SLAs are enforced in monitoring
- [ ] Document PII handling and access controls per RA 10173
- [ ] Test full backup restore before go-live

### Kubernetes / Helm Deployment

```bash
# Build and push image
docker build -f Dockerfile.airflow -t yourregistry/aml-airflow:1.0.0 .
docker push yourregistry/aml-airflow:1.0.0

# Deploy with Helm (example)
helm install bsp-aml-pipeline ./helm-charts/airflow \
  --namespace aml \
  --values production-values.yaml
```

---

## Legal & Compliance

**Jurisdiction**: Republic of the Philippines

| Regulation       | Scope                                                   |
| ---------------- | ------------------------------------------------------- |
| RA 9160 (AMLA)   | Anti-Money Laundering Act; STR 5-day filing requirement |
| RA 10927         | Enhanced AMLC powers                                    |
| BSP Circular 706 | Manual of Regulations for Banks; CTR ₱500,000 threshold |
| RA 10173         | Data Privacy Act; PII masking requirements              |
| AMLC Circulars   | Money Services Business rules and ERS filing format     |

**Data Retention**: 10 years minimum (RA 9160 §12)

**Reporting SLAs**:

- CTR: Filed within **1 banking day** of covered transaction
- STR: Filed within **5 Philippine working days** of determination

Both reports are filed to: **AMLC (Anti-Money Laundering Council)**

---

## Maintenance Notes

- **Maintenance window**: Schedule outside 1:00–6:00 AM PHT to avoid pipeline conflicts
- **dbt docs**: Regenerate after any model changes; SQL inline comments are the primary lineage documentation
- **Holiday table**: Update `seeds/ph_non_working_days.csv` annually with new PH public holidays
