# dags/src/db.py
# Database connection helper for BSP/AMLA pipeline

import os
import logging
from typing import Optional
from contextlib import contextmanager

from psycopg2.pool import SimpleConnectionPool

logger = logging.getLogger(__name__)


class DatabasePool:
    """PostgreSQL connection pool manager"""

    _instance: Optional['DatabasePool'] = None
    _pool: Optional[SimpleConnectionPool] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(DatabasePool, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        if self._pool is None:
            self._pool = self._create_pool()

    @staticmethod
    def _create_pool():
        """Create connection pool"""
        db_config = {
            'host': os.getenv('DBT_POSTGRES_HOST', 'postgres'),
            'port': int(os.getenv('DBT_POSTGRES_PORT', 5432)),
            'database': os.getenv('DBT_POSTGRES_DBNAME', 'aml_compliance_db'),
            'user': os.getenv('DBT_POSTGRES_USER', 'aml_pipeline'),
            'password': os.getenv('DBT_POSTGRES_PASSWORD', 'aml_pipeline_pwd'),
        }

        try:
            pool = SimpleConnectionPool(1, 20, **db_config)
            logger.info("Created PostgreSQL connection pool")
            return pool
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}")
            raise

    @contextmanager
    def get_connection(self):
        """Get connection from pool"""
        conn = None
        try:
            conn = self._pool.getconn()
            yield conn
        finally:
            if conn:
                self._pool.putconn(conn)

    def close_all_connections(self):
        """Close all connections in pool"""
        if self._pool:
            self._pool.closeall()
            logger.info("Closed all database connections")


def get_db_pool() -> DatabasePool:
    """Get singleton database pool"""
    return DatabasePool()


def execute_query(query: str, params: Optional[tuple] = None, fetch_one: bool = False):
    """Execute query and return results"""
    pool = get_db_pool()
    with pool.get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, params)
            if fetch_one:
                return cursor.fetchone()
            return cursor.fetchall()
        finally:
            cursor.close()


def execute_update(query: str, params: tuple = None) -> int:
    """Execute update/insert and return row count"""
    pool = get_db_pool()
    with pool.get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, params)
            conn.commit()
            return cursor.rowcount
        except Exception as e:
            conn.rollback()
            raise
        finally:
            cursor.close()
