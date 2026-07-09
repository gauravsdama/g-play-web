from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from typing import Any

from .config import LOGS_DIR, ensure_runtime_dirs

ensure_runtime_dirs()

LOG_FILE = LOGS_DIR / "vantabeat-api.log"

logger = logging.getLogger("vantabeat.api")
logger.setLevel(logging.INFO)

if not logger.handlers:
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    file_handler = RotatingFileHandler(LOG_FILE, maxBytes=1_000_000, backupCount=5)
    file_handler.setFormatter(formatter)
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)


def log_event(message: str, **fields: Any) -> None:
    if fields:
        extra = " ".join([f"{key}={value}" for key, value in fields.items()])
        logger.info(f"{message} | {extra}")
    else:
        logger.info(message)


def log_error(message: str, **fields: Any) -> None:
    if fields:
        extra = " ".join([f"{key}={value}" for key, value in fields.items()])
        logger.error(f"{message} | {extra}")
    else:
        logger.error(message)


class YtdlpLogger:
    def debug(self, message: str) -> None:
        logger.debug(message)

    def warning(self, message: str) -> None:
        logger.warning(message)

    def error(self, message: str) -> None:
        logger.error(message)
