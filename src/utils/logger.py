# dags/src/logger.py
# Structured JSON logging for BSP/AMLA pipeline

import logging
import json
import os
from datetime import datetime


class JsonFormatter(logging.Formatter):
    """JSON formatter for structured logging"""

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON"""
        log_obj = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno,
        }

        # Add exception info if present
        if record.exc_info:
            log_obj['exception'] = self.formatException(record.exc_info)

        # Add extra fields
        if hasattr(record, 'task_id'):
            log_obj['task_id'] = record.task_id
        if hasattr(record, 'dag_id'):
            log_obj['dag_id'] = record.dag_id
        if hasattr(record, 'execution_date'):
            log_obj['execution_date'] = str(record.execution_date)

        return json.dumps(log_obj)


def setup_logging(name: str, level: str = None) -> logging.Logger:
    """Setup logger with JSON formatter"""
    if level is None:
        level = os.getenv('LOG_LEVEL', 'INFO')

    logger = logging.getLogger(name)
    logger.setLevel(getattr(logging, level))

    # Console handler with JSON formatter
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(JsonFormatter())
    logger.addHandler(console_handler)

    return logger
