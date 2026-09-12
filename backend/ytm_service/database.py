"""
Database module proxy for backward compatibility.
The implementation has been refactored into domain mixins in `backend/ytm_service/db/`.
"""
from .db import (
    Database,
    db,
    _escape_like,
    CREATE_TABLES_SQL,
    CoreDbMixin,
    MusicDbMixin,
    SyncDbMixin,
    PlaylistDbMixin,
    UserDbMixin,
    FamilyDbMixin,
)

__all__ = [
    "Database",
    "db",
    "_escape_like",
    "CREATE_TABLES_SQL",
    "CoreDbMixin",
    "MusicDbMixin",
    "SyncDbMixin",
    "PlaylistDbMixin",
    "UserDbMixin",
    "FamilyDbMixin",
]
