# dags/src/generate_transactions.py
# Synthetic transaction data generation for BSP/AMLA compliance pipeline
# Generates realistic banking transaction data with AML pattern injection

import os
import logging
import random
from datetime import datetime, timedelta
from uuid import uuid4
from typing import List, Dict

import psycopg2
from psycopg2.extras import RealDictCursor
from faker import Faker
import pytz

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TransactionGenerator:
    """Generate realistic banking transactions with AML patterns"""

    def __init__(self, db_config: Dict, seed: int = 42):
        self.db_config = db_config
        self.fake = Faker('en_PH')
        Faker.seed(seed)
        random.seed(seed)
        self.ph_tz = pytz.timezone('Asia/Manila')

    def connect_db(self):
        """Connect to PostgreSQL"""
        try:
            conn = psycopg2.connect(**self.db_config)
            logger.info("Connected to PostgreSQL")
            return conn
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise

    def generate_transactions(self, volume: int = 5000, aml_injection_pct: float = 0.20) -> List[Dict]:
        """
        Generate synthetic transactions

        Args:
            volume: Number of transactions to generate
            aml_injection_pct: Percentage of records with AML patterns (0-1)

        Returns:
            List of transaction dictionaries
        """
        transactions = []
        aml_count = int(volume * aml_injection_pct)
        normal_count = volume - aml_count

        logger.info(
            f"Generating {volume} transactions ({aml_count} with AML patterns, {normal_count} normal)")

        # Get customer list from database
        conn = self.connect_db()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT customer_id, branch_code FROM staging.raw_customers LIMIT 100")
        customers = cursor.fetchall()
        cursor.close()
        conn.close()

        if not customers:
            logger.warning("No customers found - generating test data")
            customers = [{'customer_id': f'CUST{i:06d}',
                          'branch_code': 'MKT001'} for i in range(100)]

        # Generate normal transactions
        for i in range(normal_count):
            txn = self._create_normal_transaction(
                customers[i % len(customers)])
            transactions.append(txn)

        # Generate transactions with AML patterns
        for i in range(aml_count):
            pattern_type = random.choice(
                ['STRUCTURING', 'LAYERING', 'DORMANCY', 'ROUND_NUMBER'])
            txn = self._create_aml_pattern_transaction(
                customers[i % len(customers)],
                pattern_type
            )
            transactions.append(txn)

        logger.info(f"Generated {len(transactions)} transactions")
        return transactions

    def _create_normal_transaction(self, customer: Dict) -> Dict:
        """Create a normal transaction"""
        txn_date = datetime.now(self.ph_tz) - \
            timedelta(days=random.randint(0, 30))

        return {
            'txn_id': str(uuid4()),
            'customer_id': customer['customer_id'],
            'branch_code': customer['branch_code'],
            'txn_date_ph': txn_date.date(),
            'txn_time_ph': txn_date.time(),
            'txn_type': random.choices(['CASH', 'RTGS', 'PESONet', 'InstaPay'], weights=[0.40, 0.25, 0.20, 0.15], k=1)[0],
            'txn_channel': random.choices(['BRANCH', 'ATM', 'ONLINE', 'MOBILE'], weights=[0.30, 0.25, 0.35, 0.10], k=1)[0],
            'transaction_direction': random.choices(['DEBIT', 'CREDIT'], weights=[0.45, 0.55]),
            'amount_local': round(random.exponential(50000, 1)[0], 2),
            'currency_code': 'PHP',
            'amount_php': round(random.exponential(50000, 1)[0], 2),
            'counterparty_name': self.fake.name(),
            'counterparty_account': f"1234{''.join(random.choice('0123456789') for _ in range(10))}",
            'counterparty_bank': random.choice(['BDO', 'BPI', 'METROBANK', 'UNIONBANK', 'EASTWEST']),
            'purpose_code': random.choice(['TRAD', 'FEXP', 'FDIR', 'OTHR']),
            'purpose_description': self.fake.sentence(),
            'reference_number': f"REF{self.fake.uuid4()[:12]}",
            'source_system': 'TEMENOS',
            'batch_id': os.getenv('BATCH_ID', 'manual_run'),
        }

    def _create_aml_pattern_transaction(self, customer: Dict, pattern_type: str) -> Dict:
        """Create transactions with AML patterns"""
        txn_date = datetime.now(self.ph_tz) - \
            timedelta(days=random.randint(0, 7))

        base_txn = {
            'txn_id': str(uuid4()),
            'customer_id': customer['customer_id'],
            'branch_code': customer['branch_code'],
            'txn_date_ph': txn_date.date(),
            'txn_time_ph': txn_date.time(),
            'txn_channel': random.choice(['BRANCH', 'ONLINE', 'MOBILE']),
            'transaction_direction': 'DEBIT',
            'currency_code': 'PHP',
            'purpose_code': random.choice(['TRAD', 'FEXP', 'FDIR', 'OTHR']),
            'counterparty_name': self.fake.name(),
            'counterparty_account': f"1234{''.join(random.choice('0123456789') for _ in range(10))}",
            'counterparty_bank': random.choice(['BDO', 'BPI', 'METROBANK']),
            'source_system': 'TEMENOS',
            'batch_id': os.getenv('BATCH_ID', 'manual_run'),
            'reference_number': f"REF{self.fake.uuid4()[:12]}",
        }

        # Inject pattern-specific amounts
        if pattern_type == 'STRUCTURING':
            base_txn['txn_type'] = 'CASH'
            base_txn['amount_local'] = round(
                random.uniform(450000, 499999), 2)
            base_txn['amount_php'] = base_txn['amount_local']
            base_txn['purpose_description'] = 'Cash withdrawal'

        elif pattern_type == 'LAYERING':
            base_txn['txn_type'] = random.choice(['RTGS', 'PESONet'])
            base_txn['amount_local'] = round(
                random.uniform(100000, 500000), 2)
            base_txn['amount_php'] = base_txn['amount_local']
            base_txn['purpose_description'] = 'Fund transfer'

        elif pattern_type == 'ROUND_NUMBER':
            base_txn['txn_type'] = 'CASH'
            base_txn['amount_local'] = random.choice(
                [500000, 1000000, 5000000])
            base_txn['amount_php'] = float(base_txn['amount_local'])
            base_txn['purpose_description'] = 'Large withdrawal'

        elif pattern_type == 'DORMANCY':
            base_txn['txn_type'] = 'CASH'
            base_txn['amount_local'] = round(
                random.uniform(100000, 500000), 2)
            base_txn['amount_php'] = base_txn['amount_local']
            base_txn['purpose_description'] = 'Dormant account activity'

        return base_txn

    def insert_transactions(self, transactions: List[Dict]) -> int:
        """Insert transactions into staging table"""
        conn = self.connect_db()
        cursor = conn.cursor()

        insert_sql = """
            INSERT INTO staging.raw_transactions (
                txn_id, customer_id, branch_code, txn_date_ph, txn_time_ph,
                txn_type, txn_channel, transaction_direction,
                amount_local, currency_code, amount_php,
                counterparty_name, counterparty_account, counterparty_bank,
                purpose_code, purpose_description, reference_number,
                source_system, batch_id
            ) VALUES (
                %(txn_id)s, %(customer_id)s, %(branch_code)s, %(txn_date_ph)s, %(txn_time_ph)s,
                %(txn_type)s, %(txn_channel)s, %(transaction_direction)s,
                %(amount_local)s, %(currency_code)s, %(amount_php)s,
                %(counterparty_name)s, %(counterparty_account)s, %(counterparty_bank)s,
                %(purpose_code)s, %(purpose_description)s, %(reference_number)s,
                %(source_system)s, %(batch_id)s
            )
            ON CONFLICT DO NOTHING
        """
        try:
            cursor.executemany(insert_sql, transactions)
            conn.commit()
            rows_inserted = cursor.rowcount
            logger.info(f"Inserted {rows_inserted} transactions")
            return rows_inserted
        except Exception as e:
            conn.rollback()
            logger.error(f"Error inserting transactions: {e}")
            raise
        finally:
            cursor.close()
            conn.close()
