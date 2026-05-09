# dags/aml_monthly_report.py

import csv
import pendulum
from datetime import timedelta
from pathlib import Path

from airflow.sdk import dag
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.operators.bash import BashOperator

from src.utils.db import get_db_pool


def export_ctr_report(**context):
    """Export CTR report in AMLC ERS format"""

    # Airflow 3.x: use data_interval_start (equivalent to old execution_date)
    report_dt = context['data_interval_start']
    report_month = report_dt.strftime('%Y%m')
    report_dir = Path(f'/reports/{report_dt.year}/{report_dt.month:02d}')
    report_dir.mkdir(parents=True, exist_ok=True)

    output_file = report_dir / f'ctr_report_{report_month}.csv'

    pool = get_db_pool()
    query = """
        SELECT
            ctr_id,
            customer_id,
            branch_code,
            txn_date_ph,
            amount_php,
            ctr_type,
            filing_status,
            filing_date
        FROM gold.fct_covered_transactions
        WHERE EXTRACT(YEAR FROM txn_date_ph) = %s
          AND EXTRACT(MONTH FROM txn_date_ph) = %s
        ORDER BY txn_date_ph DESC
    """

    with pool.get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, (report_dt.year, report_dt.month))
        rows = cursor.fetchall()

        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['CTR ID', 'Customer ID', 'Branch', 'Txn Date',
                            'Amount (PHP)', 'Type', 'Status', 'Filed Date'])
            writer.writerows(rows)

        cursor.close()

    print(f"Exported {len(rows)} CTRs to {output_file}")
    return str(output_file)


def export_str_report(**context):
    """Export STR report in AMLC ERS format"""

    report_dt = context['data_interval_start']
    report_month = report_dt.strftime('%Y%m')
    report_dir = Path(f'/reports/{report_dt.year}/{report_dt.month:02d}')
    report_dir.mkdir(parents=True, exist_ok=True)

    output_file = report_dir / f'str_report_{report_month}.csv'

    pool = get_db_pool()
    query = """
        SELECT
            str_id,
            customer_id,
            branch_code,
            str_determination_ts,
            max_risk_score,
            indicator_count,
            filing_status,
            filing_urgency
        FROM gold.fct_suspicious_transactions
        WHERE EXTRACT(YEAR FROM str_determination_ts) = %s
          AND EXTRACT(MONTH FROM str_determination_ts) = %s
        ORDER BY str_determination_ts DESC
    """

    with pool.get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(query, (report_dt.year, report_dt.month))
        rows = cursor.fetchall()

        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['STR ID', 'Customer ID', 'Branch', 'Determination Date',
                            'Risk Score', 'Indicators', 'Status', 'Urgency'])
            writer.writerows(rows)

        cursor.close()

    print(f"Exported {len(rows)} STRs to {output_file}")
    return str(output_file)


default_args = {
    'owner': 'aml-compliance-team',
    'retries': 1,
    'retry_delay': timedelta(minutes=10),
    'email_on_failure': False,
    'execution_timeout': timedelta(hours=4),
}


@dag(
    dag_id='aml_monthly_report',
    default_args=default_args,
    description='Monthly BSP/AMLC compliance report generation',
    schedule='0 6 1 * *',
    start_date=pendulum.datetime(2026, 5, 8, tz='UTC'),
    catchup=False,
    tags=['aml', 'compliance', 'bsp', 'reporting', 'monthly'],
)
def aml_monthly_report():

    query_ctr = PythonOperator(
        task_id='export_ctr_report',
        python_callable=export_ctr_report,
    )

    query_str = PythonOperator(
        task_id='export_str_report',
        python_callable=export_str_report,
    )

    # Fixed Jinja template — data_interval_start replaces execution_date
    summary_report = BashOperator(
        task_id='generate_summary_report',
        bash_command='''
            echo "Monthly Compliance Report Summary"
            echo "Report Date: {{ data_interval_start }}"
            echo "Generated: $(date)"
            echo "Reports saved to /reports/{{ data_interval_start.year }}/{{ '%02d' % data_interval_start.month }}/"
        ''',
    )

    [query_ctr, query_str] >> summary_report


aml_monthly_report()
