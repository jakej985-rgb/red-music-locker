"""Database core initialization, schema definition, and connection lifecycle."""
import aiosqlite
import asyncio
import json
import logging
import os
import shutil
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..config import settings, DEFAULT_DATA_DIR
from .base import logger, _escape_like

CREATE_TABLES_SQL = """
CREATE TABLE IF NOT EXISTS music_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT UNIQUE NOT NULL,
    filename TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    title TEXT,
    track_number INTEGER,
    disc_number INTEGER,
    duration REAL,
    format TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    modified_time REAL NOT NULL,
    file_hash TEXT,
    metadata_hash TEXT,
    verification_status TEXT DEFAULT 'UNVERIFIED',
    verification_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ytm_uploads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    entity_id TEXT UNIQUE NOT NULL,
    video_id TEXT,
    upload_video_id TEXT,
    upload_url TEXT,
    source_type TEXT DEFAULT 'ytm_upload',
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    duration REAL,
    like_status TEXT,
    thumbnail TEXT,
    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS matches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    music_file_id INTEGER NOT NULL,
    ytm_upload_id TEXT NOT NULL,
    match_type TEXT NOT NULL,
    match_score REAL NOT NULL,
    sync_decision TEXT DEFAULT 'REVIEW',
    decision_reason TEXT,
    confirmed BOOLEAN DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(music_file_id) REFERENCES music_files(id) ON DELETE CASCADE,
    UNIQUE(music_file_id, ytm_upload_id)
);

CREATE TABLE IF NOT EXISTS sync_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    music_file_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error TEXT,
    attempts INTEGER DEFAULT 0,
    source_type TEXT DEFAULT 'ytm_upload',
    source_id TEXT,
    source_url TEXT,
    expected_duration REAL,
    downloaded_source_id TEXT,
    verified BOOLEAN DEFAULT 0,
    verification_status TEXT DEFAULT 'PENDING',
    verification_reason TEXT,
    original_file_hash TEXT,
    downloaded_file_hash TEXT,
    replacement_allowed BOOLEAN DEFAULT 0,
    FOREIGN KEY(music_file_id) REFERENCES music_files(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS needs_help_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    video_id TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    thumbnail TEXT,
    source TEXT,
    reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS file_replacements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_path TEXT NOT NULL,
    original_sha256 TEXT NOT NULL,
    original_size INTEGER NOT NULL,
    original_mtime REAL NOT NULL,
    replacement_source_id TEXT NOT NULL,
    replacement_path TEXT,
    backup_path TEXT,
    replacement_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS replicated_playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    source_playlist_id TEXT NOT NULL,
    source_playlist_name TEXT NOT NULL,
    destination_playlist_id TEXT NOT NULL,
    destination_playlist_name TEXT NOT NULL,
    enabled BOOLEAN DEFAULT 1,
    sync_interval_seconds INTEGER DEFAULT 300,
    replica_mode TEXT DEFAULT '1to1_youtube',
    last_source_revision TEXT,
    last_sync_at TIMESTAMP,
    last_sync_status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, source_playlist_id, destination_playlist_id)
);

CREATE TABLE IF NOT EXISTS replicated_playlist_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    replicated_playlist_id INTEGER NOT NULL,
    source_track_id TEXT,
    source_video_id TEXT,
    locker_upload_id TEXT,
    action TEXT NOT NULL,
    reason TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(replicated_playlist_id) REFERENCES replicated_playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS replicated_playlist_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    replicated_playlist_id INTEGER NOT NULL,
    revision TEXT NOT NULL,
    track_count INTEGER NOT NULL,
    tracks_json TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(replicated_playlist_id) REFERENCES replicated_playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER',
    is_active BOOLEAN NOT NULL DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_sessions (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ytm_accounts (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    account_name TEXT,
    account_identifier TEXT,
    auth_reference TEXT,
    encrypted_credentials TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_verified_at TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_settings (
    user_id TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY(user_id, key),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS families (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS family_members (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'MEMBER',
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    show_account_in_family BOOLEAN NOT NULL DEFAULT 1,
    allow_family_uploads BOOLEAN NOT NULL DEFAULT 1,
    allow_family_playlists BOOLEAN NOT NULL DEFAULT 0,
    allow_family_sync BOOLEAN NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(family_id, user_id),
    FOREIGN KEY(family_id) REFERENCES families(id) ON DELETE CASCADE,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS family_invitations (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    token TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL DEFAULT 'MEMBER',
    created_by_user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    accepted_at TIMESTAMP,
    accepted_by_user_id TEXT,
    FOREIGN KEY(family_id) REFERENCES families(id) ON DELETE CASCADE,
    FOREIGN KEY(created_by_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_music_files_path ON music_files(path);
CREATE INDEX IF NOT EXISTS idx_music_files_artist_title ON music_files(artist, title);
CREATE INDEX IF NOT EXISTS idx_ytm_uploads_entity ON ytm_uploads(entity_id);
CREATE INDEX IF NOT EXISTS idx_matches_music_file ON matches(music_file_id);
CREATE INDEX IF NOT EXISTS idx_sync_jobs_status ON sync_jobs(status);
CREATE INDEX IF NOT EXISTS idx_needs_help_video ON needs_help_tracks(video_id);
CREATE INDEX IF NOT EXISTS idx_file_replacements_path ON file_replacements(original_path);
CREATE INDEX IF NOT EXISTS idx_replicated_playlists_source ON replicated_playlists(source_playlist_id);
CREATE INDEX IF NOT EXISTS idx_replicated_playlist_events_rep_id ON replicated_playlist_events(replicated_playlist_id);
CREATE INDEX IF NOT EXISTS idx_replicated_playlist_snapshots_rep_id ON replicated_playlist_snapshots(replicated_playlist_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_app_sessions_token ON app_sessions(token);
CREATE INDEX IF NOT EXISTS idx_app_sessions_user_id ON app_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_ytm_accounts_user_id ON ytm_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_families_owner ON families(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user_id ON family_members(user_id);
CREATE INDEX IF NOT EXISTS idx_family_members_family_id ON family_members(family_id);
CREATE INDEX IF NOT EXISTS idx_family_invitations_token ON family_invitations(token);
CREATE INDEX IF NOT EXISTS idx_family_invitations_family_id ON family_invitations(family_id);
"""


class CoreDbMixin:
    """Database lifecycle, schema migrations, and settings storage."""
    def __init__(self, db_path: Optional[Path] = None):
        self._custom_db_path = db_path

    @property
    def db_path(self) -> Path:
        return self._custom_db_path or settings.db_path

    @db_path.setter
    def db_path(self, val: Optional[Path]):
        self._custom_db_path = val

    @asynccontextmanager
    async def get_connection(self):
        async with aiosqlite.connect(self.db_path, timeout=60.0) as conn:
            conn.row_factory = aiosqlite.Row
            await conn.execute("PRAGMA foreign_keys = ON;")
            await conn.execute("PRAGMA busy_timeout = 60000;")
            yield conn

    async def init_db(self):
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        async with self.get_connection() as db:
            await db.execute("PRAGMA journal_mode = WAL;")
            await db.execute("PRAGMA synchronous = NORMAL;")
            await db.execute("PRAGMA wal_autocheckpoint = 1000;")
            await db.execute("PRAGMA cache_size = -64000;")
            await db.executescript(CREATE_TABLES_SQL)
            
            # Ensure upload identity columns exist on existing databases
            async with db.execute("PRAGMA table_info(ytm_uploads)") as cursor:
                cols = [row["name"] for row in await cursor.fetchall()]
                if "upload_video_id" not in cols:
                    await db.execute("ALTER TABLE ytm_uploads ADD COLUMN upload_video_id TEXT")
                if "upload_url" not in cols:
                    await db.execute("ALTER TABLE ytm_uploads ADD COLUMN upload_url TEXT")
                if "source_type" not in cols:
                    await db.execute("ALTER TABLE ytm_uploads ADD COLUMN source_type TEXT DEFAULT 'ytm_upload'")

            # Ensure sync_decision columns exist on existing databases
            async with db.execute("PRAGMA table_info(matches)") as cursor:
                m_cols = [row["name"] for row in await cursor.fetchall()]
                if "sync_decision" not in m_cols:
                    await db.execute("ALTER TABLE matches ADD COLUMN sync_decision TEXT DEFAULT 'REVIEW'")
                if "decision_reason" not in m_cols:
                    await db.execute("ALTER TABLE matches ADD COLUMN decision_reason TEXT")

            # Ensure Phase 10 source/integrity columns exist on sync_jobs
            async with db.execute("PRAGMA table_info(sync_jobs)") as cursor:
                sj_cols = [row["name"] for row in await cursor.fetchall()]
                columns_to_add = [
                    ("source_type", "TEXT DEFAULT 'ytm_upload'"),
                    ("source_id", "TEXT"),
                    ("source_url", "TEXT"),
                    ("expected_duration", "REAL"),
                    ("downloaded_source_id", "TEXT"),
                    ("verified", "BOOLEAN DEFAULT 0"),
                    ("verification_status", "TEXT DEFAULT 'PENDING'"),
                    ("verification_reason", "TEXT"),
                    ("original_file_hash", "TEXT"),
                    ("downloaded_file_hash", "TEXT"),
                    ("replacement_allowed", "BOOLEAN DEFAULT 0"),
                ]
                for col_name, col_def in columns_to_add:
                    if col_name not in sj_cols:
                        await db.execute(f"ALTER TABLE sync_jobs ADD COLUMN {col_name} {col_def}")

            # Ensure verification columns exist on music_files
            async with db.execute("PRAGMA table_info(music_files)") as cursor:
                mf_cols = [row["name"] for row in await cursor.fetchall()]
                if "verification_status" not in mf_cols:
                    await db.execute("ALTER TABLE music_files ADD COLUMN verification_status TEXT DEFAULT 'UNVERIFIED'")
                if "verification_reason" not in mf_cols:
                    await db.execute("ALTER TABLE music_files ADD COLUMN verification_reason TEXT")

            # Ensure user_id ownership columns exist on tables (Phase L)
            tables_needing_user_id = ["replicated_playlists", "ytm_uploads", "sync_jobs", "needs_help_tracks"]
            for tbl in tables_needing_user_id:
                async with db.execute(f"PRAGMA table_info({tbl})") as cursor:
                    t_cols = [row["name"] for row in await cursor.fetchall()]
                    if "user_id" not in t_cols:
                        await db.execute(f"ALTER TABLE {tbl} ADD COLUMN user_id TEXT")

            # Ensure family/multi-account columns exist on sync_jobs (Section 36)
            async with db.execute("PRAGMA table_info(sync_jobs)") as cursor:
                sj_cols = [row["name"] for row in await cursor.fetchall()]
                family_job_cols = [
                    ("family_id", "TEXT"),
                    ("requested_by_user_id", "TEXT"),
                    ("destination_user_id", "TEXT"),
                    ("youtube_music_account_id", "TEXT"),
                ]
                for col_name, col_def in family_job_cols:
                    if col_name not in sj_cols:
                        await db.execute(f"ALTER TABLE sync_jobs ADD COLUMN {col_name} {col_def}")

            # Migrate replicated_playlists constraint if it has old 2-column unique constraint
            async with db.execute("SELECT sql FROM sqlite_master WHERE name = 'replicated_playlists'") as cursor:
                rp_row = await cursor.fetchone()
                if rp_row and "UNIQUE(source_playlist_id, destination_playlist_id)" in rp_row["sql"]:
                    logger.info("Migrating replicated_playlists table constraint to include user_id...")
                    await db.execute("PRAGMA foreign_keys = OFF;")
                    await db.execute("""
                        CREATE TABLE replicated_playlists_new (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            user_id TEXT,
                            source_playlist_id TEXT NOT NULL,
                            source_playlist_name TEXT NOT NULL,
                            destination_playlist_id TEXT NOT NULL,
                            destination_playlist_name TEXT NOT NULL,
                            enabled BOOLEAN DEFAULT 1,
                            sync_interval_seconds INTEGER DEFAULT 300,
                            last_source_revision TEXT,
                            last_sync_at TIMESTAMP,
                            last_sync_status TEXT,
                            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            UNIQUE(user_id, source_playlist_id, destination_playlist_id)
                        );
                    """)
                    await db.execute("""
                        INSERT INTO replicated_playlists_new (
                            id, user_id, source_playlist_id, source_playlist_name,
                            destination_playlist_id, destination_playlist_name,
                            enabled, sync_interval_seconds, last_source_revision,
                            last_sync_at, last_sync_status, created_at, updated_at
                        )
                        SELECT
                            id, user_id, source_playlist_id, source_playlist_name,
                            destination_playlist_id, destination_playlist_name,
                            enabled, sync_interval_seconds, last_source_revision,
                            last_sync_at, last_sync_status, created_at, updated_at
                        FROM replicated_playlists;
                    """)
                    await db.execute("DROP TABLE replicated_playlists;")
                    await db.execute("ALTER TABLE replicated_playlists_new RENAME TO replicated_playlists;")
                    await db.execute("PRAGMA foreign_keys = ON;")

            await db.execute("CREATE INDEX IF NOT EXISTS idx_replicated_playlists_user_id ON replicated_playlists(user_id);")
            await db.execute("CREATE INDEX IF NOT EXISTS idx_ytm_uploads_user_id ON ytm_uploads(user_id);")
            await db.execute("CREATE INDEX IF NOT EXISTS idx_sync_jobs_user_id ON sync_jobs(user_id);")
            await db.execute("CREATE INDEX IF NOT EXISTS idx_sync_jobs_family_id ON sync_jobs(family_id);")
            await db.execute("CREATE INDEX IF NOT EXISTS idx_sync_jobs_destination_user_id ON sync_jobs(destination_user_id);")

            await db.commit()

        # Bootstrap initial admin user & single-user installation migration if no users exist
        await self._ensure_admin_bootstrapped()
        await self.reconcile_stuck_sync_jobs()

    async def get_setting(self, key: str, default: Any = None) -> Any:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute("SELECT value FROM settings WHERE key = ?", (key,)) as cursor:
                row = await cursor.fetchone()
                if row:
                    try:
                        return json.loads(row["value"])
                    except Exception:
                        return row["value"]
                return default

    async def set_setting(self, key: str, value: Any):
        val_str = json.dumps(value) if not isinstance(value, str) else value
        async with self.get_connection() as db:
            await db.execute(
                "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, val_str)
            )
            await db.commit()

    # Music Files operations
    async def backup_database(self, dest_dir: Optional[Path] = None) -> str:
        import shutil
        b_dir = dest_dir or (self.db_path.parent / "backups")
        b_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        backup_file = b_dir / f"ytm_sync_backup_{timestamp}.db"
        
        async with self.get_connection() as db:
            await db.execute("PRAGMA wal_checkpoint(FULL);")
        
        shutil.copy2(self.db_path, backup_file)
        return str(backup_file)


