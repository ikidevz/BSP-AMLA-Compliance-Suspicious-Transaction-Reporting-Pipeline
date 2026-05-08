# I Built a Production-Grade AML Compliance Pipeline for Philippine Banking — Here's How

_What happens when you take BSP regulatory deadlines, AMLC filing requirements, Philippine banking law, synthetic transaction data with real AML pattern injection, a medallion data architecture, Apache Airflow 3, dbt, PostgreSQL row-level security, and PII masking under RA 10173 — and wire them all together into a single automated pipeline? This is that project._

---

There's a category of data engineering project that doesn't get talked about enough — the kind where getting the logic wrong doesn't just break a dashboard, it means a bank misses a regulatory filing deadline, faces a BSP penalty, or worse, lets a financial crime slip through.

That's the space I decided to build in.

Over the past few months, I designed and built an end-to-end **AML (Anti-Money Laundering) Compliance and Suspicious Transaction Reporting pipeline** — a fully containerized, orchestrated, regulation-aware data system targeting the Philippine banking sector. This post walks through what I built, why I made the decisions I did, and what I learned.

---

## The Problem Space

The Philippines has one of Southeast Asia's more detailed AML regulatory frameworks. Under **Republic Act 9160 (AMLA)** and **BSP Circular 706**, covered institutions must:

- File a **Covered Transaction Report (CTR)** for any cash transaction ≥ ₱500,000 — within **1 banking day**
- File a **Suspicious Transaction Report (STR)** for transactions showing anomalous behavior — within **5 Philippine working days** of determination (no minimum amount)
- Maintain full audit trails for **10 years** minimum
- Mask customer PII per **RA 10173** (the Data Privacy Act)

That's not a vague business requirement. That's a hard, legally enforceable SLA with criminal penalties for non-compliance.

The engineering challenge: build a system that can ingest raw transaction data daily, run AML pattern detection automatically, produce compliance-ready reports, and do all of this reliably enough to stake regulatory standing on it.

---

## What I Built

A fully automated data pipeline with these components working together:

```
Synthetic Data Generation
        ↓
   Apache Airflow 3         ← orchestration & scheduling
        ↓
      dbt 1.8              ← medallion transformations + AML logic
        ↓
   PostgreSQL 16           ← staging / bronze / silver / gold
        ↓
     Metabase              ← compliance dashboards
```

Everything runs in Docker Compose — spin it up locally with a single command.

---

## The Data Architecture: Medallion, But With a Purpose

I used the medallion pattern (staging → bronze → silver → gold), but each layer has a deliberate compliance meaning — not just "raw" vs "clean."

**Staging** is the landing zone. Raw transactions arrive here from the Python generators. No transformation, no business logic. This layer, with full unmasked PII, is restricted to the `aml_pipeline` database role only.

**Bronze** is validation. dbt staging models enforce schema contracts, reject nulls on critical fields, and flag records that can't be processed. Think of it as the "did this data actually arrive correctly?" checkpoint.

**Silver** is where AML happens. This is the interesting layer.

**Gold** is compliance-ready output — the tables that feed reports, dashboards, and eventually AMLC filings. PII is masked here per RA 10173, making it safe to expose to Metabase and analyst roles.

---

## The AML Detection Models

### Structuring

Structuring is the practice of breaking up large transactions into smaller ones specifically to avoid the ₱500,000 CTR threshold. It's one of the clearest behavioral signals in financial crime.

My detection logic uses a 7-day rolling window:

```sql
WHERE txn_count_7d >= 3
  AND txn_sum_7d >= 450000
  AND amount_php < 490000
```

Three or more transactions, summing close to but under the threshold, in a week — that's a structuring flag. Base risk score: **70**.

### Layering

Layering is about velocity. Money moves in, money moves out, almost nothing is left — the goal being to obscure the origin. I detect this with a 48-hour in/out analysis:

```sql
WHERE amount_in_48h > 50000
  AND amount_out_48h > 50000
  AND net_position_pct < 10
```

High inflow, high outflow, near-zero net. Base risk score: **65**.

### Covered Transaction Detection

Three patterns trigger a CTR:

- Single cash transaction ≥ ₱500,000
- Related transactions on the same banking day totaling ₱500,000+
- FOREX transactions ≥ USD 10,000 equivalent

### STR Signal Aggregation

The STR model is a composite. It pulls together every signal — structuring, layering, PEP status, FATF jurisdiction flags, KYC deficiencies, watchlist matches, dormancy anomalies, round-number transactions — and scores them into a single risk rating per customer per period. If that score crosses the threshold, it surfaces as an STR candidate with the exact indicators that triggered it.

---

## The Airflow DAGs

### Daily Pipeline — `aml_compliance_pipeline`

Runs Mon–Sat at 2:00 AM PHT. The graph is intentionally parallel at the ingestion stage:

```
[generate_customers]    ──┐
[generate_transactions] ──┼──> [dbt_init] → [dbt_seed] → [dbt_run] → [dbt_test] → [mark_complete]
[generate_kyc_documents]──┘
```

Customer data, transaction data, and KYC documents are generated in parallel. dbt only starts once all three are complete. This keeps the pipeline fast on the critical path while being correct about dependencies.

I'm using **Apache Airflow 3.2.1** with the new `@dag` decorator syntax and `data_interval_start` instead of the deprecated `execution_date`. Small thing, but important for anyone building on Airflow 3 — the old Jinja context variables break silently.

### Monthly Report — `aml_monthly_report`

Runs on the 1st of each month at 6:00 AM PHT. Parallel CTR and STR export, then a summary task. Outputs are CSV files in AMLC ERS format, dropped into `/reports/{year}/{month}/` for downstream filing.

---

## Synthetic Data Generation

Real banking data is obviously off the table for a portfolio project. So I built a synthetic data generator that produces _behaviorally realistic_ transactions — not just random numbers.

The generator supports configurable AML pattern injection. By default, 20% of transactions carry some AML signal — structuring patterns, round numbers, FATF-country counterparties, PEP involvement. The remaining 80% are normal retail banking activity.

This matters for testing. A detection model that only ever sees random noise is useless. You need labeled anomalies to validate that your detection logic actually fires when it should.

---

## Data Privacy by Design

RA 10173 (the Philippine Data Privacy Act) isn't optional. From day one, I designed the data model around it:

- Full customer PII (name, SSS number, TIN) is retained in staging and bronze — but those layers are locked behind the `aml_pipeline` PostgreSQL role
- Gold-layer tables expose only masked data: names as `A***N`, ID numbers as `***1234`
- Row-level security policies in PostgreSQL enforce this at the database level — even if someone misconfigures application permissions, the DB won't serve unmasked data to the wrong role

```
gold.dim_customers  →  metabase_amlc_user  →  masked only
staging.*           →  aml_pipeline role   →  full data
```

Security that lives in the application layer is fragile. Security that lives in the database is structural.

---

## What I'd Do Differently

**Email alerting on SLA breach.** Right now a failed pipeline run surfaces in Airflow's UI, but there's no active push notification when a CTR generation task fails and the 1-day deadline is at risk. In production, that needs to be a pager alert.

**Incremental dbt models.** The current setup runs full refreshes on every dbt run. For the transaction volume in this project (5,000/day synthetic), that's fine. At real bank scale — millions of transactions — you'd need incremental models with proper `unique_key` strategies on the fact tables.

**dbt Cloud or a data catalog.** The lineage is great in dbt docs, but it's not surfaced anywhere persistent. For a compliance context where auditors need to trace exactly how a CTR was computed, you want lineage stored externally, not regenerated on demand.

---

## Stack Summary

| Layer            | Tool           | Version |
| ---------------- | -------------- | ------- |
| Orchestration    | Apache Airflow | 3.2.1   |
| Transformation   | dbt            | 1.8.5   |
| Database         | PostgreSQL     | 16      |
| BI / Dashboards  | Metabase       | Latest  |
| Task Queue       | Redis + Celery | 7.2     |
| Containerization | Docker Compose | —       |
| Language         | Python         | 3.12    |

---

## Try It Yourself

The full project is on GitHub — everything you need to run it locally:

```bash
git clone https://github.com/ikidevz/BSP-AMLA-Compliance-Suspicious-Transaction-Reporting-Pipeline.git
cd BSP-AMLA-Compliance-Suspicious-Transaction-Reporting-Pipeline
cp .env.example .env
docker compose up -d --build

# Trigger the pipeline
docker compose exec airflow-scheduler airflow dags trigger aml_compliance_pipeline
```

Airflow UI at `localhost:8080`, Metabase at `localhost:3000`.

---

## Final Thought

The most interesting data engineering problems aren't about scale or clever architecture for its own sake. They're about understanding the domain well enough that the pipeline actually means something — where a wrong join condition has a real-world consequence.

Building inside the Philippine AML regulatory framework forced me to think about data that way. Every model answers a specific legal question. Every filing deadline is a hard constraint. The data architecture isn't abstract — it directly maps to what a compliance officer needs to do their job.

That's the kind of engineering I want to keep building.

---

_If you're working on something similar — financial data pipelines, compliance automation, or just Philippine fintech data problems — I'd love to connect._

_The full source, dbt models, and setup guide are available on GitHub at [ikidevz/BSP-AMLA-Compliance-Suspicious-Transaction-Reporting-Pipeline](https://github.com/ikidevz/BSP-AMLA-Compliance-Suspicious-Transaction-Reporting-Pipeline). See the README for architecture details and quick start instructions._
