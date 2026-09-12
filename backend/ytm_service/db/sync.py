"""Database mixin for sync jobs, queue management, and needs-help track tracking."""
import aiosqlite
import logging
import sqlite3
from datetime import datetime, timezone, timedelta
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..models import SyncJob, UploadStatus, MusicFile
from .base import logger


class SyncDbMixin:
    """Sync job queue, execution status, and needs-help track operations."""
    async def reconcile_stuck_sync_jobs(self, max_attempts: int = 3) -> dict[str, int]:
        """Reconcile jobs left in 'uploading' or 'verifying' from a crash or SIGTERM.
        Resets jobs to 'queued' if attempts < max_attempts, or marks them 'failed' if attempts >= max_attempts.
        """
        async with self.get_connection() as db:
            cursor = await db.execute(
                """
                UPDATE sync_jobs
                SET status = 'queued', error = 'Re-queued after server restart'
                WHERE status IN ('uploading', 'verifying') AND attempts < ?
                """,
                (max_attempts,)
            )
            requeued_count = cursor.rowcount

            cursor = await db.execute(
                """
                UPDATE sync_jobs
                SET status = 'failed', error = 'Exceeded retry limit (interrupted)'
                WHERE status IN ('uploading', 'verifying') AND attempts >= ?
                """,
                (max_attempts,)
            )
            failed_count = cursor.rowcount
            await db.commit()
            return {"requeued": requeued_count, "failed": failed_count}

    # Settings operations
    def _row_to_sync_job(self, data: dict) -> SyncJob:
        mf_fields = ["path", "filename", "artist", "album", "title", "duration", "format", "file_size", "modified_time"]
        mf_data = {k: data[k] for k in mf_fields if k in data}
        mf_data["id"] = data.get("music_file_id")

        for k in [
            "source_type", "source_id", "source_url", "expected_duration",
            "downloaded_source_id", "verified", "verification_status",
            "verification_reason", "downloaded_file_hash", "replacement_allowed"
        ]:
            if k in data:
                mf_data[k] = data[k]

        status_val = data.get("status", "queued")
        try:
            status_enum = UploadStatus(status_val)
        except ValueError:
            status_enum = status_val

        return SyncJob(
            id=data.get("id"),
            user_id=data.get("user_id"),
            family_id=data.get("family_id"),
            requested_by_user_id=data.get("requested_by_user_id"),
            destination_user_id=data.get("destination_user_id") or data.get("user_id"),
            youtube_music_account_id=data.get("youtube_music_account_id"),
            music_file_id=data.get("music_file_id"),
            status=status_enum,
            started_at=data.get("started_at"),
            completed_at=data.get("completed_at"),
            error=data.get("error"),
            attempts=data.get("attempts", 0),
            ytm_entity_id=data.get("ytm_upload_id"),
            source_type=data.get("source_type", "ytm_upload"),
            source_id=data.get("source_id"),
            source_url=data.get("source_url"),
            expected_duration=data.get("expected_duration"),
            downloaded_source_id=data.get("downloaded_source_id"),
            verified=bool(data.get("verified", 0)),
            verification_status=data.get("verification_status", "PENDING"),
            verification_reason=data.get("verification_reason"),
            original_file_hash=data.get("original_file_hash"),
            downloaded_file_hash=data.get("downloaded_file_hash"),
            replacement_allowed=bool(data.get("replacement_allowed", 0)),
            music_file=MusicFile(**mf_data)
        )

    async def create_sync_job(
        self,
        music_file_id: int,
        source_type: str = "ytm_upload",
        source_id: Optional[str] = None,
        source_url: Optional[str] = None,
        expected_duration: Optional[float] = None,
        original_file_hash: Optional[str] = None,
        replacement_allowed: bool = False,
        verification_status: str = "PENDING",
        user_id: Optional[str] = None,
        family_id: Optional[str] = None,
        requested_by_user_id: Optional[str] = None,
        destination_user_id: Optional[str] = None,
        youtube_music_account_id: Optional[str] = None
    ) -> int:
        target_user = destination_user_id or user_id
        async with self.get_connection() as db:
            async with db.execute(
                """
                INSERT INTO sync_jobs (
                    music_file_id, status, attempts,
                    source_type, source_id, source_url,
                    expected_duration, original_file_hash, replacement_allowed,
                    verification_status, user_id, family_id, requested_by_user_id,
                    destination_user_id, youtube_music_account_id
                ) VALUES (?, 'queued', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id
                """,
                (
                    music_file_id, source_type, source_id, source_url,
                    expected_duration, original_file_hash, 1 if replacement_allowed else 0,
                    verification_status, target_user, family_id, requested_by_user_id,
                    target_user, youtube_music_account_id
                )
            ) as cursor:
                row = await cursor.fetchone()
                await db.commit()
                return row[0]

    async def update_sync_job(
        self,
        job_id: int,
        status: Union[UploadStatus, str],
        error: Optional[str] = None,
        increment_attempts: bool = False,
        downloaded_source_id: Optional[str] = None,
        verified: Optional[bool] = None,
        verification_status: Optional[str] = None,
        verification_reason: Optional[str] = None,
        downloaded_file_hash: Optional[str] = None
    ):
        now = datetime.now(timezone.utc).isoformat()
        status_val = status.value if hasattr(status, "value") else str(status)

        updates = ["status = ?", "error = ?"]
        params = [status_val, error]

        if increment_attempts:
            updates.append("attempts = attempts + 1")

        if status_val in ("uploading", "UPLOADING", "DOWNLOADING", "VERIFYING"):
            updates.append("started_at = COALESCE(started_at, ?)")
            params.append(now)
        elif status_val in ("verified", "VERIFIED", "failed", "FAILED", "BLOCKED"):
            updates.append("completed_at = ?")
            params.append(now)

        if downloaded_source_id is not None:
            updates.append("downloaded_source_id = ?")
            params.append(downloaded_source_id)
        if verified is not None:
            updates.append("verified = ?")
            params.append(1 if verified else 0)
        if verification_status is not None:
            updates.append("verification_status = ?")
            params.append(verification_status)
        if verification_reason is not None:
            updates.append("verification_reason = ?")
            params.append(verification_reason)
        if downloaded_file_hash is not None:
            updates.append("downloaded_file_hash = ?")
            params.append(downloaded_file_hash)

        params.append(job_id)
        query = f"UPDATE sync_jobs SET {', '.join(updates)} WHERE id = ?"

        async with self.get_connection() as db:
            await db.execute(query, tuple(params))
            await db.commit()

    async def get_next_queued_job(self) -> Optional[SyncJob]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT sj.*, mf.path, mf.filename, mf.artist, mf.album, mf.title, mf.duration, mf.format, mf.file_size, mf.modified_time
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                WHERE sj.status = 'queued'
                ORDER BY sj.id ASC LIMIT 1
                """
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                return self._row_to_sync_job(dict(row))

    async def get_sync_job_by_id(self, job_id: int) -> Optional[SyncJob]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT sj.*, mf.path, mf.filename, mf.artist, mf.album, mf.title, mf.duration, mf.format, mf.file_size, mf.modified_time,
                       m.ytm_upload_id
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                LEFT JOIN matches m ON mf.id = m.music_file_id
                WHERE sj.id = ?
                """,
                (job_id,)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                return self._row_to_sync_job(dict(row))

    async def retry_blocked_sync_job(self, job_id: int) -> Optional[SyncJob]:
        """
        Manually retry a BLOCKED sync job (Blocker 3).
        Safety Invariants:
        - Job must currently be in BLOCKED status.
        - Automatic workers ignore BLOCKED jobs.
        - Manual retry strictly locks to the EXACT same original source_type and source_id.
        - Resets status to 'queued' with attempts=0.
        """
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute("SELECT * FROM sync_jobs WHERE id = ?", (job_id,)) as cursor:
                row = await cursor.fetchone()
                if not row:
                    raise FileNotFoundError(f"Sync job {job_id} not found")
                st = row["status"]
                v_st = row["verification_status"] if "verification_status" in row.keys() else None
                if st != "BLOCKED" and v_st != "BLOCKED":
                    raise ValueError(f"Job {job_id} is not BLOCKED (current status: {st})")

                orig_source_id = row["source_id"] if "source_id" in row.keys() else None

            await db.execute(
                """
                UPDATE sync_jobs
                SET status = 'queued',
                    verification_status = 'PENDING',
                    verification_reason = 'Manual retry requested by user for original source ID ' || COALESCE(source_id, ''),
                    attempts = 0,
                    error = NULL,
                    completed_at = NULL
                WHERE id = ?
                """,
                (job_id,)
            )
            await db.commit()
        return await self.get_sync_job_by_id(job_id)

    async def get_sync_history(self, limit: int = 100) -> list[SyncJob]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT sj.*, mf.path, mf.filename, mf.artist, mf.album, mf.title, mf.duration, mf.format, mf.file_size, mf.modified_time,
                       m.ytm_upload_id
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                LEFT JOIN matches m ON mf.id = m.music_file_id
                ORDER BY sj.id DESC LIMIT ?
                """,
                (limit,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [self._row_to_sync_job(dict(row)) for row in rows]

    async def get_user_sync_history(self, user_id: str, limit: int = 100) -> list[SyncJob]:
        """Fetch sync history strictly filtered to a specific user (Phase W)."""
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT sj.*, mf.path, mf.filename, mf.artist, mf.album, mf.title, mf.duration, mf.format, mf.file_size, mf.modified_time,
                       m.ytm_upload_id
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                LEFT JOIN matches m ON mf.id = m.music_file_id
                WHERE sj.user_id = ?
                ORDER BY sj.id DESC LIMIT ?
                """,
                (user_id, limit)
            ) as cursor:
                rows = await cursor.fetchall()
                return [self._row_to_sync_job(dict(row)) for row in rows]

    async def get_active_or_queued_sync_jobs(self, limit: int = 100) -> list[SyncJob]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT sj.*, mf.path, mf.filename, mf.artist, mf.album, mf.title, mf.duration, mf.format, mf.file_size, mf.modified_time,
                       m.ytm_upload_id
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                LEFT JOIN matches m ON mf.id = m.music_file_id
                WHERE sj.status IN ('queued', 'uploading', 'verifying', 'PENDING', 'DOWNLOADING', 'VERIFYING')
                ORDER BY CASE WHEN sj.status IN ('uploading', 'DOWNLOADING', 'VERIFYING') THEN 0 ELSE 1 END, sj.id ASC LIMIT ?
                """,
                (limit,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [self._row_to_sync_job(dict(row)) for row in rows]

    async def clear_queued_sync_jobs(self):
        async with self.get_connection() as db:
            await db.execute("DELETE FROM sync_jobs WHERE status = 'queued'")
            await db.commit()

    async def upsert_needs_help_track(
        self,
        video_id: str,
        title: str,
        artist: Optional[str] = None,
        album: Optional[str] = None,
        thumbnail: Optional[str] = None,
        source: Optional[str] = None,
        reason: Optional[str] = None
    ):
        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO needs_help_tracks (video_id, title, artist, album, thumbnail, source, reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(video_id) DO UPDATE SET
                    title = excluded.title,
                    artist = excluded.artist,
                    album = excluded.album,
                    thumbnail = excluded.thumbnail,
                    source = excluded.source,
                    reason = excluded.reason,
                    created_at = CURRENT_TIMESTAMP
                """,
                (video_id, title, artist, album, thumbnail, source, reason)
            )
            await db.commit()

    async def get_needs_help_tracks(self, limit: int = 200) -> list[dict]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT * FROM needs_help_tracks ORDER BY id DESC LIMIT ?",
                (limit,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [dict(r) for r in rows]

    async def delete_needs_help_track(self, video_id: str):
        async with self.get_connection() as db:
            await db.execute("DELETE FROM needs_help_tracks WHERE video_id = ?", (video_id,))
            await db.commit()

    async def count_needs_help_tracks(self) -> int:
        async with self.get_connection() as db:
            async with db.execute("SELECT COUNT(*) FROM needs_help_tracks") as cursor:
                row = await cursor.fetchone()
                return row[0] if row else 0

    # Stats
    async def get_dashboard_counts(self, user_id: Optional[str] = None) -> dict:
        async with self.get_connection() as db:
            async with db.execute("SELECT COUNT(*) FROM music_files") as c:
                local_count = (await c.fetchone())[0]

            if user_id:
                async with db.execute("SELECT COUNT(*) FROM ytm_uploads WHERE user_id = ?", (user_id,)) as c:
                    ytm_count = (await c.fetchone())[0]
            else:
                async with db.execute("SELECT COUNT(*) FROM ytm_uploads") as c:
                    ytm_count = (await c.fetchone())[0]

            async with db.execute(
                """
                SELECT COUNT(*) FROM music_files mf
                LEFT JOIN matches m ON mf.id = m.music_file_id
                LEFT JOIN (
                    SELECT music_file_id, status FROM sync_jobs s1
                    WHERE id = (SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)
                ) sj ON mf.id = sj.music_file_id
                WHERE m.id IS NULL AND (sj.status IS NULL OR sj.status NOT IN ('uploaded', 'verified', 'uploading', 'queued'))
                """
            ) as c:
                missing_count = (await c.fetchone())[0]

            async with db.execute("SELECT COUNT(DISTINCT music_file_id) FROM matches") as c:
                uploaded_count = (await c.fetchone())[0]

            failed_sql = """
                SELECT COUNT(*) FROM sync_jobs s1
                WHERE s1.status = 'failed' 
                AND id = (SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)
            """
            failed_params = ()
            if user_id:
                failed_sql += " AND s1.user_id = ?"
                failed_params = (user_id,)
            async with db.execute(failed_sql, failed_params) as c:
                failed_count = (await c.fetchone())[0]

            queue_sql = "SELECT COUNT(*) FROM sync_jobs WHERE status IN ('queued', 'uploading', 'verifying')"
            queue_params = ()
            if user_id:
                queue_sql += " AND user_id = ?"
                queue_params = (user_id,)
            async with db.execute(queue_sql, queue_params) as c:
                in_queue_count = (await c.fetchone())[0]

            return {
                "local_songs_count": local_count,
                "ytm_uploads_count": ytm_count,
                "missing_count": missing_count,
                "uploaded_count": uploaded_count,
                "failed_count": failed_count,
                "in_queue_count": in_queue_count,
            }


