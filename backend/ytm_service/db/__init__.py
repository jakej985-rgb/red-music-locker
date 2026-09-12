"""Database package providing modular mixins and the unified Database client."""
from .base import _escape_like
from .core import CoreDbMixin, CREATE_TABLES_SQL
from .music import MusicDbMixin
from .sync import SyncDbMixin
from .playlists import PlaylistDbMixin
from .users import UserDbMixin
from .family import FamilyDbMixin


class Database(
    CoreDbMixin,
    MusicDbMixin,
    SyncDbMixin,
    PlaylistDbMixin,
    UserDbMixin,
    FamilyDbMixin,
):
    """Unified Database client combining core schema, music, sync, playlist, user, and family management."""
    pass


db = Database()

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
