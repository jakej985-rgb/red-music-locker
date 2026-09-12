"""
Application constants and enumerations for Red Music Locker.
Centralizes domain filter types, formats, and magic strings (Section 31 & Q5).
"""
from enum import Enum


class UploadFilterType(str, Enum):
    """Filter types for uploaded music queries."""
    ALL = "all"
    MISSING_METADATA = "missing_metadata"
    PROPER = "proper"
    DUPLICATES = "duplicates"
    SKITS = "skits"


class SyncJobType(str, Enum):
    """Types of sync operations tracked in the queue."""
    UPLOAD = "upload"
    PLAYLIST_DOWNLOAD = "playlist_download"
    REPLACE = "replace"
    METADATA_UPDATE = "metadata_update"


class AudioFormat(str, Enum):
    """Supported audio extensions/formats."""
    MP3 = "mp3"
    FLAC = "flac"
    M4A = "m4a"
    OGG = "ogg"
    OPUS = "opus"
    WAV = "wav"
    WMA = "wma"
    AAC = "aac"
    AIFF = "aiff"


DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 500
MAX_BATCH_SIZE = 500
DEFAULT_SYNC_RETRY_LIMIT = 3
