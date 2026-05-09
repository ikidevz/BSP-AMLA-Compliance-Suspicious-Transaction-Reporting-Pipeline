# dags/src/generate_kyc.py
# Synthetic KYC document data generation

import logging
import random
from typing import List, Dict
from uuid import uuid4
from datetime import datetime, timedelta

import psycopg2
from psycopg2.extras import RealDictCursor
from faker import Faker

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class KYCGenerator:
    """Generate KYC document records"""

    def __init__(self, db_config: Dict, seed: int = 42):
        self.db_config = db_config
        self.fake = Faker('en_PH')
        Faker.seed(seed)
        random.seed(seed)

    def connect_db(self):
        """Connect to PostgreSQL"""
        try:
            conn = psycopg2.connect(**self.db_config)
            return conn
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise

    def generate_kyc_documents(self) -> List[Dict]:
        """Generate KYC documents for existing customers"""
        documents = []

        # Get all customers
        conn = self.connect_db()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT customer_id FROM staging.raw_customers")
        customers = cursor.fetchall()
        cursor.close()
        conn.close()

        logger.info(f"Generating KYC documents for {len(customers)} customers")

        doc_types = ['PASSPORT', 'NATIONAL_ID', 'DRIVERS_LICENSE', 'POSTAL_ID']

        for customer in customers:
            customer_id = customer['customer_id']

            # Most customers have 2-3 documents
            # random.sample() replaces np.random.choice(replace=False)
            num_docs = random.randint(2, 3)
            selected_doc_types = random.sample(doc_types, num_docs)

            for doc_type in selected_doc_types:
                issue_date = datetime.now() - timedelta(days=random.randint(180, 1825))

                # Expiry varies by document type
                if doc_type == 'PASSPORT':
                    expiry_years = 10
                elif doc_type == 'NATIONAL_ID':
                    expiry_years = 5
                else:
                    expiry_years = 3

                expiry_date = issue_date + timedelta(days=expiry_years * 365)

                # 15% of documents are expired
                if random.random() < 0.15:
                    expiry_date = datetime.now() - timedelta(days=random.randint(1, 365))

                doc = {
                    'document_id': str(uuid4()),
                    'customer_id': customer_id,
                    'document_type': doc_type,
                    'document_number': self.fake.uuid4()[:10].upper(),
                    'issue_date': issue_date.date(),
                    'expiry_date': expiry_date.date() if random.random() > 0.05 else None,
                    'issuing_country': 'PH',
                    'issuing_authority': 'PSA' if doc_type == 'NATIONAL_ID' else 'LTO' if doc_type == 'DRIVERS_LICENSE' else 'DFA',
                }
                documents.append(doc)

        logger.info(f"Generated {len(documents)} KYC documents")
        return documents

    def insert_kyc_documents(self, documents: List[Dict]) -> int:
        """Insert KYC documents"""
        conn = self.connect_db()
        cursor = conn.cursor()

        insert_sql = """
            INSERT INTO staging.raw_kyc_documents (
                document_id, customer_id, document_type,
                document_number, issue_date, expiry_date,
                issuing_country, issuing_authority
            ) VALUES (
                %(document_id)s, %(customer_id)s, %(document_type)s,
                %(document_number)s, %(issue_date)s, %(expiry_date)s,
                %(issuing_country)s, %(issuing_authority)s
            )
            ON CONFLICT DO NOTHING
        """

        try:
            cursor.executemany(insert_sql, documents)
            conn.commit()
            rows_inserted = cursor.rowcount
            logger.info(f"Inserted {rows_inserted} KYC documents")
            return rows_inserted
        except Exception as e:
            conn.rollback()
            logger.error(f"Error inserting KYC documents: {e}")
            raise
        finally:
            cursor.close()
            conn.close()
