"""Database mixin for replicated playlists, snapshots, and audit events."""
import aiosqlite
import json
import logging
import sqlite3
from datetime import datetime, timezone
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..models import (
    ReplicatedPlaylist,
    ReplicatedPlaylistEvent,
    SourcePlaylistSnapshot,
    SourcePlaylistTrackSnapshot
)
from .base import logger


class PlaylistDbMixin:
    """Replicated playlist CRUD, event history, and snapshot operations."""
    async def get_replicated_playlists(self, user_id: Optional[str] = None, enabled_only: bool = False) -> list[ReplicatedPlaylist]:
        """Fetch configured replicated playlist watchers, optionally filtered by user_id."""
        conditions = []
        params = []
        if user_id is not None:
            conditions.append("user_id = ?")
            params.append(user_id)
        if enabled_only:
            conditions.append("enabled = 1")

        query = "SELECT * FROM replicated_playlists"
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY id ASC"

        async with self.get_connection() as db:
            async with db.execute(query, tuple(params)) as cursor:
                rows = await cursor.fetchall()
                return [ReplicatedPlaylist(**dict(row)) for row in rows]

    async def get_replicated_playlist(self, replicated_id: int, user_id: Optional[str] = None) -> Optional[ReplicatedPlaylist]:
        """Fetch a specific replicated playlist watcher by ID, optionally verifying ownership."""
        query = "SELECT * FROM replicated_playlists WHERE id = ?"
        params = [replicated_id]
        if user_id is not None:
            query += " AND user_id = ?"
            params.append(user_id)

        async with self.get_connection() as db:
            async with db.execute(query, tuple(params)) as cursor:
                row = await cursor.fetchone()
                return ReplicatedPlaylist(**dict(row)) if row else None

    async def get_replicated_playlist_by_source_id(self, source_playlist_id: str, user_id: Optional[str] = None) -> Optional[ReplicatedPlaylist]:
        """Fetch a replicated playlist watcher by its source YouTube Music playlist ID."""
        query = "SELECT * FROM replicated_playlists WHERE source_playlist_id = ?"
        params = [source_playlist_id]
        if user_id is not None:
            query += " AND user_id = ?"
            params.append(user_id)

        async with self.get_connection() as db:
            async with db.execute(query, tuple(params)) as cursor:
                row = await cursor.fetchone()
                return ReplicatedPlaylist(**dict(row)) if row else None

    async def create_replicated_playlist(
        self,
        source_playlist_id: str,
        source_playlist_name: str,
        destination_playlist_id: str,
        destination_playlist_name: str,
        enabled: bool = True,
        sync_interval_seconds: int = 300,
        user_id: Optional[str] = None,
        replica_mode: Optional[str] = None
    ) -> int:
        """Create a new replicated playlist configuration owned by user_id."""
        async with self.get_connection() as db:
            if not replica_mode:
                if "locker" in destination_playlist_name.lower() or "upload" in destination_playlist_name.lower():
                    mode_val = "locker_only"
                else:
                    mode_val = "1to1_youtube"
            else:
                mode_val = replica_mode

            cursor = await db.execute(
                """
                INSERT INTO replicated_playlists (
                    user_id, source_playlist_id, source_playlist_name,
                    destination_playlist_id, destination_playlist_name,
                    enabled, sync_interval_seconds, replica_mode
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING id
                """,
                (
                    user_id, source_playlist_id, source_playlist_name,
                    destination_playlist_id, destination_playlist_name,
                    1 if enabled else 0, sync_interval_seconds, mode_val
                )
            )
            row = await cursor.fetchone()
            await db.commit()
            return row["id"]

    async def update_replicated_playlist(self, replicated_id: int, user_id: Optional[str] = None, **kwargs) -> Optional[ReplicatedPlaylist]:
        """Update fields of a replicated playlist configuration, verifying user_id if provided."""
        if not kwargs:
            return await self.get_replicated_playlist(replicated_id, user_id=user_id)

        set_clauses = []
        values = []
        for k, v in kwargs.items():
            if k in ("destination_playlist_id", "source_playlist_name", "destination_playlist_name", "last_source_revision", "last_sync_status", "last_sync_at", "replica_mode"):
                set_clauses.append(f"{k} = ?")
                values.append(v)
            elif k in ("enabled",):
                set_clauses.append(f"{k} = ?")
                values.append(1 if v else 0)
            elif k in ("sync_interval_seconds",):
                set_clauses.append(f"{k} = ?")
                values.append(int(v))

        set_clauses.append("updated_at = CURRENT_TIMESTAMP")
        values.append(replicated_id)

        where_clause = "WHERE id = ?"
        if user_id is not None:
            where_clause += " AND user_id = ?"
            values.append(user_id)

        async with self.get_connection() as db:
            await db.execute(
                f"UPDATE replicated_playlists SET {', '.join(set_clauses)} {where_clause}",
                tuple(values)
            )
            await db.commit()
        return await self.get_replicated_playlist(replicated_id, user_id=user_id)

    async def delete_replicated_playlist(self, replicated_id: int, user_id: Optional[str] = None) -> bool:
        """Delete a replicated playlist configuration, verifying user_id if provided."""
        query = "DELETE FROM replicated_playlists WHERE id = ?"
        params = [replicated_id]
        if user_id is not None:
            query += " AND user_id = ?"
            params.append(user_id)

        async with self.get_connection() as db:
            cursor = await db.execute(query, tuple(params))
            await db.commit()
            return cursor.rowcount > 0

    async def record_replicated_playlist_event(
        self,
        replicated_playlist_id: int,
        action: str,
        source_track_id: Optional[str] = None,
        source_video_id: Optional[str] = None,
        locker_upload_id: Optional[str] = None,
        reason: Optional[str] = None
    ):
        """Record an audit event for playlist reconciliation (ADD, REMOVE, MOVE, NOOP, EXCLUDE)."""
        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO replicated_playlist_events (
                    replicated_playlist_id, source_track_id, source_video_id,
                    locker_upload_id, action, reason
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (replicated_playlist_id, source_track_id, source_video_id, locker_upload_id, action, reason)
            )
            await db.commit()

    async def get_replicated_playlist_events(self, replicated_playlist_id: int, limit: int = 100) -> list[dict]:
        """Fetch audit trail events for a replicated playlist."""
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM replicated_playlist_events WHERE replicated_playlist_id = ? ORDER BY timestamp DESC LIMIT ?",
                (replicated_playlist_id, limit)
            ) as cursor:
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]

    async def save_replicated_playlist_snapshot(
        self,
        replicated_playlist_id: int,
        revision: str,
        tracks: list[dict]
    ) -> int:
        """Store source playlist snapshot (Section 4 of plan) to detect changes."""
        tracks_json = json.dumps(tracks)
        async with self.get_connection() as db:
            cursor = await db.execute(
                """
                INSERT INTO replicated_playlist_snapshots (
                    replicated_playlist_id, revision, track_count, tracks_json
                ) VALUES (?, ?, ?, ?)
                RETURNING id
                """,
                (replicated_playlist_id, revision, len(tracks), tracks_json)
            )
            row = await cursor.fetchone()
            await db.commit()
            return row["id"]

    async def get_latest_replicated_playlist_snapshot(self, replicated_playlist_id: int) -> Optional[dict]:
        """Get the most recent source playlist snapshot for a replica."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT * FROM replicated_playlist_snapshots
                WHERE replicated_playlist_id = ?
                ORDER BY created_at DESC LIMIT 1
                """,
                (replicated_playlist_id,)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                try:
                    data["tracks"] = json.loads(data.get("tracks_json") or "[]")
                except Exception:
                    data["tracks"] = []
                return data

    # --- Multi-User Management Methods (Phases D through Q) ---


