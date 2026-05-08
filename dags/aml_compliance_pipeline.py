# dags/aml_compliance_pipeline.py
# BSP/AMLA Compliance & Suspicious Transaction Reporting Pipeline
# Daily DAG: Data generation → dbt processing → compliance checks
# Schedule: 2:00 AM PHT Mon–Sat (excluding Sundays)

import os
import pendulum
from datetime import timedelta

from airflow.sdk import dag
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.operators.bash import BashOperator

from src.generate_kyc import KYCGenerator
from src.generate_customers import CustomerGenerator
from src.generate_transactions import TransactionGenerator


default_args = {
    'owner': 'aml-compliance-team',
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'email_on_failure': False,
    'email_on_retry': False,
    'execution_timeout': timedelta(hours=2),
}

db_config = {
    'host': os.getenv('DBT_POSTGRES_HOST', 'postgres'),
    'port': int(os.getenv('DBT_POSTGRES_PORT', 5432)),
    'database': os.getenv('DBT_POSTGRES_DBNAME', 'aml_compliance_db'),
    'user': os.getenv('DBT_POSTGRES_USER', 'aml_pipeline'),
    'password': os.getenv('DBT_POSTGRES_PASSWORD', 'aml_pipeline_pwd'),
}

DBT_ENV = {
    "PATH": "/home/airflow/.local/bin:/usr/local/bin:/usr/bin:/bin",
    "POSTGRES_HOST":     os.getenv("DBT_POSTGRES_HOST",     "postgres"),
    "POSTGRES_PORT":     os.getenv("DBT_POSTGRES_PORT",     "5432"),
    "POSTGRES_DB":       os.getenv("DBT_POSTGRES_DBNAME",  "aml_compliance_db"),
    "POSTGRES_USER":     os.getenv("DBT_POSTGRES_USER",     "aml_pipeline"),
    "POSTGRES_PASSWORD": os.getenv("DBT_POSTGRES_PASSWORD", "aml_pipeline_pwd"),
}
DBT_DIR = "/opt/airflow/dbt"


def generate_transactions_task():
    """Generate synthetic transactions"""

    volume = int(os.getenv('SYNTHETIC_DATA_VOLUME_TXN', 5000))
    aml_injection_pct = float(
        os.getenv('SYNTHETIC_DATA_AML_INJECTION_PCT', 0.20))

    generator = TransactionGenerator(
        db_config,
        seed=42
    )

    transactions = generator.generate_transactions(volume, aml_injection_pct)
    rows_inserted = generator.insert_transactions(transactions)

    return {'rows_inserted': rows_inserted}


def generate_customers_task():
    """Generate/refresh synthetic customers"""
    volume = int(os.getenv('SYNTHETIC_DATA_VOLUME_CUSTOMERS', 500))

    generator = CustomerGenerator(db_config, seed=42)
    customers = generator.generate_customers(volume)
    rows_inserted = generator.insert_customers(customers)

    return {'rows_inserted': rows_inserted}


def generate_kyc_task():
    """Generate KYC documents"""

    generator = KYCGenerator(db_config, seed=42)
    documents = generator.generate_kyc_documents()
    rows_inserted = generator.insert_kyc_documents(documents)

    return {'rows_inserted': rows_inserted}


@dag(
    dag_id='aml_compliance_pipeline',
    default_args=default_args,
    description='Daily BSP/AMLA compliance and STR reporting pipeline',
    # schedule='0 2 * * 1-6',  # 2:00 AM PHT, Mon-Sat (UTC+8: 18:00 UTC prev day)
    schedule=None,
    start_date=pendulum.datetime(2025, 1, 1, tz='Asia/Manila'),
    catchup=False,
    tags=['aml', 'compliance', 'bsp', 'daily'],
)
def aml_compliance_pipeline():

    generate_txn = PythonOperator(
        task_id='generate_transactions',
        python_callable=generate_transactions_task,
    )

    generate_cust = PythonOperator(
        task_id='generate_customers',
        python_callable=generate_customers_task,
    )

    generate_kyc = PythonOperator(
        task_id='generate_kyc_documents',
        python_callable=generate_kyc_task,
    )

    dbt_init = BashOperator(
        task_id="dbt_init",
        bash_command=f"cd {DBT_DIR} && dbt deps --profiles-dir .",
        env=DBT_ENV,
    )

    dbt_seed = BashOperator(
        task_id='dbt_seed',
        bash_command=f"""
        cd {DBT_DIR} && \
        dbt seed \
            --profiles-dir . \
            --project-dir . \
            --target dev \
            --no-partial-parse
        """,
        env=DBT_ENV,
    )

    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command=f"""
        cd {DBT_DIR} && \
        dbt run \
            --profiles-dir . \
            --project-dir . \
            --target dev \
            --no-partial-parse
    """,
        env=DBT_ENV,
    )

    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command=f"""
            cd {DBT_DIR} && \
            dbt test \
                --profiles-dir . \
                --project-dir . \
                --target dev
        """,
        env=DBT_ENV,
    )

    mark_complete = BashOperator(
        task_id='mark_pipeline_complete',
        bash_command='echo "AML Compliance Pipeline execution completed successfully at $(date)"',
    )

    generate_cust >> [generate_txn,
                      generate_kyc] >> dbt_init >> dbt_seed >> dbt_run >> dbt_test >> mark_complete


aml_compliance_pipeline()
