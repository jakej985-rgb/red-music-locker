"""Base database utilities and shared helpers."""
import logging

logger = logging.getLogger("ytm_sync.database")


def _escape_like(value: str) -> str:
    """Escape SQL LIKE wildcard characters in user-supplied search input.
    Prevents users from injecting % or _ to match unintended patterns."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
