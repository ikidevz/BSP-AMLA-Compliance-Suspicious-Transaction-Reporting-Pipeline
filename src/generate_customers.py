# dags/src/generate_customers.py
# Synthetic customer data generation for BSP/AMLA compliance pipeline
# Generates realistic customer profiles with valid Philippine ID formats

import os
import logging
from typing import List, Dict
from uuid import uuid4
from datetime import datetime, timedelta

import psycopg2
from psycopg2.extras import RealDictCursor
from faker import Faker
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CustomerGenerator:
    """Generate realistic customer profiles"""

    def __init__(self, db_config: Dict, seed: int = 42):
        self.db_config = db_config
        self.fake = Faker('en_PH')
        Faker.seed(seed)
        np.random.seed(seed)

    def connect_db(self):
        """Connect to PostgreSQL"""
        try:
            conn = psycopg2.connect(**self.db_config)
            logger.info("Connected to PostgreSQL")
            return conn
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise

    def generate_sss_number(self) -> str:
        """Generate valid SSS number format: XX-XXXXXXX-X"""
        part1 = f"{np.random.randint(10, 99)}"
        part2 = f"{np.random.randint(1000000, 9999999)}"
        part3 = f"{np.random.randint(1, 9)}"
        return f"{part1}-{part2}-{part3}"

    def generate_tin_number(self) -> str:
        """Generate valid TIN format: XXX-XXX-XXX-XXX"""
        parts = [f"{np.random.randint(100, 999)}" for _ in range(4)]
        return "-".join(parts)

    def generate_philhealth_id(self) -> str:
        """Generate PhilHealth ID: 12 digit number"""
        return ''.join([str(np.random.randint(0, 9)) for _ in range(12)])

    def generate_customers(self, volume: int = 500, pep_ratio: float = 0.05) -> List[Dict]:
        """
        Generate synthetic customers

        Args:
            volume: Number of customers to generate
            pep_ratio: Ratio of customers marked as PEP (0-1)

        Returns:
            List of customer dictionaries
        """
        customers = []
        pep_count = int(volume * pep_ratio)

        logger.info(
            f"Generating {volume} customers ({pep_count} PEP, {volume - pep_count} regular)")

        # Get branches from database
        conn = self.connect_db()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        try:
            cursor.execute("SELECT branch_code FROM bronze.ph_branches")
            branches = [row['branch_code'] for row in cursor.fetchall()]
        except Exception as e:
            logger.warning(
                f"Branch lookup failed, using fallback branch list: {e}")
            branches = []
        finally:
            cursor.close()
            conn.close()

        if not branches:
            branches = ['MKT001', 'MKT002', 'MKT003', 'MKT004', 'MKT005', 'MKT006', 'MKT007', 'CEB001', 'CEB002', 'CEB003', 'CEB004', 'CEB005', 'DVO001', 'DVO002', 'DVO003', 'DVO004', 'CDO001',
                        'CDO002', 'CDO003', 'ILO001', 'ILO002', 'ILO003', 'LEG001', 'LEG002', 'PUA001', 'PUA002', 'TUG001', 'TUG002', 'BAG001', 'VIG001', 'TAC001', 'ORM001', 'LEZ001', 'SAM001', 'PAG001', 'ZAM001']

        # Generate PEP customers
        for i in range(pep_count):
            cust = self._create_customer(
                branches[i % len(branches)],
                is_pep=True
            )
            customers.append(cust)

        # Generate regular customers
        for i in range(volume - pep_count):
            cust = self._create_customer(
                branches[i % len(branches)],
                is_pep=False
            )
            customers.append(cust)

        logger.info(f"Generated {len(customers)} customers")
        return customers

    def _create_customer(self, branch_code: str, is_pep: bool = False) -> Dict:
        """Create a single customer record"""
        customer_type = np.random.choice(
            ['INDIVIDUAL', 'CORPORATE', 'SOLEPROPRIETOR', 'NGO'],
            p=[0.70, 0.15, 0.10, 0.05]
        )

        # Risk tier - more diverse for realistic distribution
        if is_pep:
            risk_tier = 'HIGH'
        else:
            risk_tier = np.random.choice(
                ['LOW', 'MEDIUM', 'HIGH'], p=[0.60, 0.30, 0.10])

        account_opened_date = datetime.now() - timedelta(days=np.random.randint(365, 1825))

        return {
            'customer_id': f"CUST{str(uuid4())[:12].upper()}",
            'customer_name': self.fake.name(),
            'customer_type': customer_type,
            'sss_number': self.generate_sss_number(),
            'tin_number': self.generate_tin_number(),
            'philhealth_id': self.generate_philhealth_id(),
            'date_of_birth': self.fake.date_of_birth(minimum_age=18, maximum_age=80),
            'nationality': 'PH',
            'is_pep': is_pep,
            'pep_determination_date': datetime.now().date() if is_pep else None,
            'risk_tier': risk_tier,
            'account_status': np.random.choice(['ACTIVE', 'DORMANT', 'RESTRICTED'], p=[0.90, 0.08, 0.02]),
            'account_opened_date': account_opened_date.date(),
            'branch_code': branch_code,
            'customer_segment': np.random.choice(['RETAIL', 'SME', 'CORPORATE'], p=[0.60, 0.30, 0.10]),
            'kyc_status': 'COMPLETE',
            'kyc_last_update_date': (datetime.now() - timedelta(days=np.random.randint(1, 365))).date(),
        }

    def insert_customers(self, customers: List[Dict]) -> int:
        """Insert customers into staging table"""
        conn = self.connect_db()
        cursor = conn.cursor()

        insert_sql = """
            INSERT INTO staging.raw_customers (
                customer_id, customer_name, customer_type,
                sss_number, tin_number, philhealth_id,
                date_of_birth, nationality, is_pep, pep_determination_date,
                risk_tier, account_status, account_opened_date,
                branch_code, customer_segment, kyc_status, kyc_last_update_date
            ) VALUES (
                %(customer_id)s, %(customer_name)s, %(customer_type)s,
                %(sss_number)s, %(tin_number)s, %(philhealth_id)s,
                %(date_of_birth)s, %(nationality)s, %(is_pep)s, %(pep_determination_date)s,
                %(risk_tier)s, %(account_status)s, %(account_opened_date)s,
                %(branch_code)s, %(customer_segment)s, %(kyc_status)s, %(kyc_last_update_date)s
            )
            ON CONFLICT (customer_id) DO UPDATE SET
                customer_name = EXCLUDED.customer_name,
                risk_tier = EXCLUDED.risk_tier,
                kyc_last_update_date = EXCLUDED.kyc_last_update_date
        """

        try:
            cursor.executemany(insert_sql, customers)
            conn.commit()
            rows_inserted = cursor.rowcount
            logger.info(f"Inserted/updated {rows_inserted} customers")
            return rows_inserted
        except Exception as e:
            conn.rollback()
            logger.error(f"Error inserting customers: {e}")
            raise
        finally:
            cursor.close()
            conn.close()
