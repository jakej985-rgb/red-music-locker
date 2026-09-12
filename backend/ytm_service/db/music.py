"""Database mixin for music files, uploads, matching, and file replacements."""
import aiosqlite
import asyncio
import json
import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..models import MusicFile, YtmUpload, MatchRecord, UploadStatus, MatchType
from .base import logger, _escape_like


class MusicDbMixin:
    """MusicFile, YtmUpload, Match, and file replacement database operations."""
    async def upsert_music_file(self, file_info: dict) -> int:
        now = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                INSERT INTO music_files (
                    path, filename, artist, album, title, track_number, disc_number,
                    duration, format, file_size, modified_time, file_hash, metadata_hash,
                    updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    filename=excluded.filename,
                    artist=excluded.artist,
                    album=excluded.album,
                    title=excluded.title,
                    track_number=excluded.track_number,
                    disc_number=excluded.disc_number,
                    duration=excluded.duration,
                    format=excluded.format,
                    file_size=excluded.file_size,
                    modified_time=excluded.modified_time,
                    file_hash=excluded.file_hash,
                    metadata_hash=excluded.metadata_hash,
                    updated_at=excluded.updated_at
                RETURNING id
                """,
                (
                    file_info["path"],
                    file_info["filename"],
                    file_info.get("artist"),
                    file_info.get("album"),
                    file_info.get("title"),
                    file_info.get("track_number"),
                    file_info.get("disc_number"),
                    file_info.get("duration"),
                    file_info["format"],
                    file_info["file_size"],
                    file_info["modified_time"],
                    file_info.get("file_hash"),
                    file_info.get("metadata_hash"),
                    now,
                )
            ) as cursor:
                row = await cursor.fetchone()
                await db.commit()
                return row[0]

    async def get_music_files(
        self,
        filter_status: Optional[str] = None,
        search: Optional[str] = None,
        limit: int = 200,
        offset: int = 0
    ) -> list[MusicFile]:
        query = """
            SELECT 
                mf.*,
                COALESCE(sj.status, 
                    CASE 
                        WHEN m.id IS NOT NULL THEN 'verified'
                        ELSE 'not_uploaded'
                    END
                ) as upload_status,
                m.ytm_upload_id as matched_upload_id,
                m.match_score as match_score
            FROM music_files mf
            LEFT JOIN matches m ON mf.id = m.music_file_id
            LEFT JOIN (
                SELECT s1.* FROM sync_jobs s1
                JOIN (SELECT music_file_id, MAX(id) as max_id FROM sync_jobs GROUP BY music_file_id) s2
                ON s1.id = s2.max_id
            ) sj ON mf.id = sj.music_file_id
            WHERE 1=1
        """
        params: list[Any] = []

        if search:
            query += " AND (mf.title LIKE ? ESCAPE '\\' OR mf.artist LIKE ? ESCAPE '\\' OR mf.album LIKE ? ESCAPE '\\' OR mf.filename LIKE ? ESCAPE '\\')"
            s_param = f"%{_escape_like(search)}%"
            params.extend([s_param, s_param, s_param, s_param])

        if filter_status == "uploaded":
            query += " AND (m.id IS NOT NULL OR sj.status IN ('uploaded', 'verified'))"
        elif filter_status == "missing":
            query += " AND (m.id IS NULL AND (sj.status IS NULL OR sj.status NOT IN ('uploaded', 'verified', 'uploading', 'queued')))"
        elif filter_status == "failed":
            query += " AND sj.status = 'failed'"
        elif filter_status == "queued":
            query += " AND sj.status IN ('queued', 'uploading', 'verifying')"

        query += " ORDER BY mf.artist ASC, mf.album ASC, mf.track_number ASC, mf.title ASC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(query, params) as cursor:
                rows = await cursor.fetchall()
                results = []
                for row in rows:
                    data = dict(row)
                    raw_st = data.pop("upload_status", "not_uploaded")
                    matched_id = data.pop("matched_upload_id", None)
                    m_score = data.pop("match_score", None)
                    item = MusicFile(**data)
                    try:
                        item.upload_status = UploadStatus(raw_st)
                    except ValueError:
                        item.upload_status = UploadStatus.NOT_UPLOADED
                    item.matched_upload_id = matched_id
                    item.match_score = m_score
                    results.append(item)
                return results

    async def get_music_file_by_id(self, file_id: int) -> Optional[MusicFile]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            query = """
                SELECT 
                    mf.*,
                    (
                        CASE 
                            WHEN m.id IS NOT NULL THEN 'verified'
                            WHEN sj.status IS NOT NULL THEN sj.status
                            ELSE 'not_uploaded'
                        END
                    ) as upload_status,
                    m.ytm_upload_id as matched_upload_id,
                    m.match_score as match_score
                FROM music_files mf
                LEFT JOIN matches m ON mf.id = m.music_file_id
                LEFT JOIN (
                    SELECT s1.* FROM sync_jobs s1
                    JOIN (SELECT music_file_id, MAX(id) as max_id FROM sync_jobs GROUP BY music_file_id) s2
                    ON s1.id = s2.max_id
                ) sj ON mf.id = sj.music_file_id
                WHERE mf.id = ?
            """
            async with db.execute(query, (file_id,)) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                raw_st = data.pop("upload_status", "not_uploaded")
                matched_id = data.pop("matched_upload_id", None)
                m_score = data.pop("match_score", None)
                item = MusicFile(**data)
                try:
                    item.upload_status = UploadStatus(raw_st)
                except ValueError:
                    item.upload_status = UploadStatus.NOT_UPLOADED
                item.matched_upload_id = matched_id
                item.match_score = m_score
                return item

    async def update_music_file_metadata(
        self,
        file_id: int,
        title: str,
        artist: Optional[str] = None,
        album: Optional[str] = None,
        track_number: Optional[int] = None
    ) -> Optional[MusicFile]:
        from .normalizer import compute_metadata_hash
        now = datetime.now(timezone.utc).isoformat()

        for attempt in range(5):
            try:
                async with self.get_connection() as db:
                    async with db.execute("SELECT duration FROM music_files WHERE id = ?", (file_id,)) as cursor:
                        row = await cursor.fetchone()
                        if not row:
                            return None
                        duration = row["duration"]

                    meta_hash = compute_metadata_hash(artist, album, title, duration)

                    await db.execute(
                        """
                        UPDATE music_files
                        SET title = ?, artist = ?, album = ?, track_number = ?, metadata_hash = ?, updated_at = ?
                        WHERE id = ?
                        """,
                        (title, artist, album, track_number, meta_hash, now, file_id)
                    )
                    await db.commit()
                    break
            except sqlite3.OperationalError as e:
                if "locked" in str(e).lower() and attempt < 4:
                    await asyncio.sleep(0.3 * (attempt + 1))
                else:
                    raise

        return await self.get_music_file_by_id(file_id)

    async def get_all_local_songs(self) -> list[dict]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute("SELECT path, title, artist, album, duration FROM music_files") as cursor:
                rows = await cursor.fetchall()
                return [dict(r) for r in rows]

    # YTM Uploads
    async def upsert_ytm_upload(self, upload_info: Union[dict, Any]):
        if hasattr(upload_info, "model_dump"):
            upload_info = upload_info.model_dump()
        elif hasattr(upload_info, "dict"):
            upload_info = upload_info.dict()

        now = datetime.now(timezone.utc).isoformat()
        vid = upload_info.get("video_id") or upload_info.get("upload_video_id")
        upload_url = upload_info.get("upload_url") or (f"https://www.youtube.com/watch?v={vid}" if vid else None)
        source_type = upload_info.get("source_type") or "ytm_upload"

        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO ytm_uploads (
                    entity_id, video_id, upload_video_id, upload_url, source_type,
                    title, artist, album, duration, like_status, thumbnail, last_seen, user_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(entity_id) DO UPDATE SET
                    video_id=excluded.video_id,
                    upload_video_id=excluded.upload_video_id,
                    upload_url=excluded.upload_url,
                    source_type=excluded.source_type,
                    title=excluded.title,
                    artist=excluded.artist,
                    album=excluded.album,
                    duration=excluded.duration,
                    like_status=excluded.like_status,
                    thumbnail=excluded.thumbnail,
                    last_seen=excluded.last_seen,
                    user_id=COALESCE(excluded.user_id, ytm_uploads.user_id)
                """,
                (
                    upload_info["entity_id"],
                    vid,
                    vid,
                    upload_url,
                    source_type,
                    upload_info["title"],
                    upload_info.get("artist"),
                    upload_info.get("album"),
                    upload_info.get("duration"),
                    upload_info.get("like_status"),
                    upload_info.get("thumbnail"),
                    now,
                    upload_info.get("user_id"),
                )
            )
            await db.commit()

    async def get_all_ytm_uploads(self, user_id: Optional[str] = None) -> list[YtmUpload]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            if user_id:
                async with db.execute("SELECT * FROM ytm_uploads WHERE user_id = ?", (user_id,)) as cursor:
                    rows = await cursor.fetchall()
                    return [YtmUpload(**dict(r)) for r in rows]
            else:
                async with db.execute("SELECT * FROM ytm_uploads") as cursor:
                    rows = await cursor.fetchall()
                    return [YtmUpload(**dict(r)) for r in rows]

    async def get_ytm_upload_by_entity_id(self, entity_id: str) -> Optional[YtmUpload]:
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute("SELECT * FROM ytm_uploads WHERE entity_id = ?", (entity_id,)) as cursor:
                row = await cursor.fetchone()
                if row:
                    return YtmUpload(**dict(row))
                return None

    async def get_ytm_upload_by_video_id(self, video_id: str, user_id: Optional[str] = None) -> Optional[YtmUpload]:
        """Lookup an upload by its YouTube video_id."""
        if not video_id:
            return None
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            if user_id:
                async with db.execute(
                    "SELECT * FROM ytm_uploads WHERE (video_id = ? OR upload_video_id = ?) AND user_id = ? LIMIT 1",
                    (video_id, video_id, user_id)
                ) as cursor:
                    row = await cursor.fetchone()
                    if row:
                        return YtmUpload(**dict(row))
            else:
                async with db.execute("SELECT * FROM ytm_uploads WHERE video_id = ? OR upload_video_id = ? LIMIT 1", (video_id, video_id)) as cursor:
                    row = await cursor.fetchone()
                    if row:
                        return YtmUpload(**dict(row))
                return None

    async def find_ytm_upload_by_title_artist(self, title: str, artist: Optional[str] = None, user_id: Optional[str] = None) -> Optional[YtmUpload]:
        """Find an existing upload matching normalized title and artist."""
        from .normalizer import normalize_text
        clean_title = normalize_text(title)
        clean_artist = normalize_text(artist) if artist else ""
        if not clean_title:
            return None
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            # Search by title prefix for fast indexing
            if user_id:
                query = "SELECT * FROM ytm_uploads WHERE title LIKE ? ESCAPE '\\' AND user_id = ? LIMIT 50"
                params = (f"%{_escape_like(title[:20])}%", user_id)
            else:
                query = "SELECT * FROM ytm_uploads WHERE title LIKE ? ESCAPE '\\' LIMIT 50"
                params = (f"%{_escape_like(title[:20])}%",)
            async with db.execute(query, params) as cursor:
                rows = await cursor.fetchall()
                for r in rows:
                    u = YtmUpload(**dict(r))
                    u_title = normalize_text(u.title)
                    u_artist = normalize_text(u.artist) if u.artist else ""
                    if u_title == clean_title:
                        if not clean_artist or not u_artist or u_artist == clean_artist:
                            return u
        return None

    async def delete_ytm_upload_record(self, entity_id: str):
        async with self.get_connection() as db:
            async with db.execute("SELECT video_id FROM ytm_uploads WHERE entity_id = ?", (entity_id,)) as cur:
                row = await cur.fetchone()
                vid = row[0] if row else None
            await db.execute("DELETE FROM matches WHERE ytm_upload_id = ?", (entity_id,))
            await db.execute("DELETE FROM ytm_uploads WHERE entity_id = ?", (entity_id,))
            if vid:
                await db.execute("DELETE FROM ytm_uploads WHERE entity_id = ?", (f"up_{vid}",))
            await db.commit()

    async def prune_deleted_ytm_uploads(self, active_entity_ids: set[str], excluded_entity_ids: set[str]):
        """Prune uploads from the local database that no longer exist on YouTube Music."""
        async with self.get_connection() as db:
            # 1. Delete all excluded/blacklisted entity IDs
            for eid in excluded_entity_ids:
                await db.execute("DELETE FROM matches WHERE ytm_upload_id = ?", (eid,))
                await db.execute("DELETE FROM ytm_uploads WHERE entity_id = ?", (eid,))

            # 2. Prune local uploads that are no longer in active_entity_ids (including artificial up_% IDs)
            async with db.execute("SELECT entity_id FROM ytm_uploads") as cursor:
                rows = await cursor.fetchall()
                local_eids = {r[0] for r in rows}

            stale_eids = local_eids - active_entity_ids
            for s_eid in stale_eids:
                await db.execute("DELETE FROM matches WHERE ytm_upload_id = ?", (s_eid,))
                await db.execute("DELETE FROM ytm_uploads WHERE entity_id = ?", (s_eid,))

            await db.commit()

    async def update_ytm_upload(
        self,
        entity_id: str,
        title: str,
        artist: Optional[str] = None,
        album: Optional[str] = None,
        thumbnail: Optional[str] = None
    ):
        """Update metadata for an existing YTM upload in the local database."""
        async with self.get_connection() as db:
            await db.execute(
                """
                UPDATE ytm_uploads
                SET title = ?, artist = ?, album = ?, thumbnail = ?
                WHERE entity_id = ?
                """,
                (title, artist, album, thumbnail, entity_id)
            )
            await db.commit()

    async def get_ytm_uploads_summary(self) -> dict:
        missing_condition = """
        (
            artist IS NULL OR artist = '' OR TRIM(LOWER(artist)) = 'unknown artist' OR TRIM(LOWER(artist)) = 'unknown'
            OR album IS NULL OR album = '' OR TRIM(LOWER(album)) = 'unknown album' OR TRIM(LOWER(album)) = 'unknown'
            OR thumbnail IS NULL OR thumbnail = ''
            OR title IS NULL OR title = ''
            OR title LIKE '%.mp3' OR title LIKE '%.flac' OR title LIKE '%.m4a' OR title LIKE '%.wav' OR title LIKE '%.opus' OR title LIKE '%.webm'
            OR title LIKE 'y2mate%' OR title LIKE 'snapsave%' OR title LIKE 'tuberipper%'
        )
        """

        skits_condition = """
        (
            (duration IS NOT NULL AND duration > 0 AND duration < 60)
            OR (duration IS NOT NULL AND duration < 90 AND (
                LOWER(title) LIKE '%skit%' 
                OR LOWER(title) LIKE '%interlude%' 
                OR LOWER(title) LIKE '%intro%'
                OR LOWER(title) LIKE '%outro%'
            ))
        )
        """

        duplicates_condition = """
        (
            (
                LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
            ) IN (
                SELECT 
                    LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                    COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
                FROM ytm_uploads
                WHERE title IS NOT NULL AND TRIM(title) != ''
                GROUP BY 
                    LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                    COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
                HAVING COUNT(*) > 1
            )
            OR
            (video_id IS NOT NULL AND TRIM(video_id) != '' AND video_id IN (
                SELECT video_id
                FROM ytm_uploads
                WHERE video_id IS NOT NULL AND TRIM(video_id) != ''
                GROUP BY video_id
                HAVING COUNT(*) > 1
            ))
        )
        """

        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                f"""
                SELECT 
                    COUNT(*) as total,
                    COUNT(CASE WHEN {missing_condition} THEN 1 END) as missing_metadata,
                    COUNT(CASE WHEN {skits_condition} THEN 1 END) as skits,
                    COUNT(CASE WHEN {duplicates_condition} THEN 1 END) as duplicates
                FROM ytm_uploads
                """
            ) as cursor:
                row = await cursor.fetchone()
                total = row["total"] if row else 0
                missing = row["missing_metadata"] if row else 0
                skits = row["skits"] if row else 0
                dups_count = row["duplicates"] if row else 0

            return {
                "total": total,
                "missing_metadata": missing,
                "duplicates": dups_count,
                "skits": skits,
                "proper": max(0, total - missing)
            }

    async def get_ytm_uploads(
        self,
        filter_type: str = "all",
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 50
    ) -> dict:
        where_clauses = []
        params = []

        missing_condition = """
        (
            artist IS NULL OR artist = '' OR TRIM(LOWER(artist)) = 'unknown artist' OR TRIM(LOWER(artist)) = 'unknown'
            OR album IS NULL OR album = '' OR TRIM(LOWER(album)) = 'unknown album' OR TRIM(LOWER(album)) = 'unknown'
            OR thumbnail IS NULL OR thumbnail = ''
            OR title IS NULL OR title = ''
            OR title LIKE '%.mp3' OR title LIKE '%.flac' OR title LIKE '%.m4a' OR title LIKE '%.wav' OR title LIKE '%.opus' OR title LIKE '%.webm'
            OR title LIKE 'y2mate%' OR title LIKE 'snapsave%' OR title LIKE 'tuberipper%'
        )
        """

        skits_condition = """
        (
            (duration IS NOT NULL AND duration > 0 AND duration < 60)
            OR (duration IS NOT NULL AND duration < 90 AND (
                LOWER(title) LIKE '%skit%' 
                OR LOWER(title) LIKE '%interlude%' 
                OR LOWER(title) LIKE '%intro%'
                OR LOWER(title) LIKE '%outro%'
            ))
        )
        """

        duplicates_condition = """
        (
            (
                LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
            ) IN (
                SELECT 
                    LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                    COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
                FROM ytm_uploads
                WHERE title IS NOT NULL AND TRIM(title) != ''
                GROUP BY 
                    LOWER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(title, '.mp3', ''), '.flac', ''), '.m4a', ''), '.wav', ''), '.opus', ''), '.webm', ''))),
                    COALESCE(NULLIF(TRIM(LOWER(artist)), 'unknown artist'), '')
                HAVING COUNT(*) > 1
            )
            OR
            (video_id IS NOT NULL AND TRIM(video_id) != '' AND video_id IN (
                SELECT video_id
                FROM ytm_uploads
                WHERE video_id IS NOT NULL AND TRIM(video_id) != ''
                GROUP BY video_id
                HAVING COUNT(*) > 1
            ))
        )
        """

        order_by = "first_seen DESC, title ASC"
        if filter_type == "missing_metadata":
            where_clauses.append(missing_condition)
        elif filter_type == "duplicates":
            where_clauses.append(duplicates_condition)
            order_by = "LOWER(TRIM(REPLACE(title, '.mp3', ''))) ASC, duration ASC, first_seen DESC"
        elif filter_type == "skits":
            where_clauses.append(skits_condition)
            order_by = "duration ASC, title ASC"
        elif filter_type == "proper":
            where_clauses.append(f"NOT {missing_condition}")

        if search:
            where_clauses.append("(title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\')")
            s_param = f"%{_escape_like(search)}%"
            params.extend([s_param, s_param, s_param])

        where_sql = ""
        if where_clauses:
            where_sql = "WHERE " + " AND ".join(where_clauses)

        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            count_query = f"SELECT COUNT(*) as cnt FROM ytm_uploads {where_sql}"
            async with db.execute(count_query, params) as cursor:
                row = await cursor.fetchone()
                total = row["cnt"] if row else 0

            offset = (page - 1) * page_size
            data_query = f"""
                SELECT * FROM ytm_uploads
                {where_sql}
                ORDER BY {order_by}
                LIMIT ? OFFSET ?
            """
            data_params = list(params) + [page_size, offset]
            async with db.execute(data_query, data_params) as cursor:
                rows = await cursor.fetchall()
                items = [YtmUpload(**dict(r)) for r in rows]

            return {
                "items": items,
                "total": total,
                "page": page,
                "page_size": page_size,
                "total_pages": (total + page_size - 1) // page_size if total > 0 else 1
            }

    # Matches
    async def save_match(
        self,
        file_id: int,
        ytm_upload_id: str,
        match_type: MatchType | str,
        score: float,
        sync_decision: Optional[str] = None,
        decision_reason: Optional[str] = None
    ):
        m_val = match_type.value if isinstance(match_type, MatchType) else str(match_type)
        decision_val = sync_decision or "REVIEW"
        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO matches (music_file_id, ytm_upload_id, match_type, match_score, sync_decision, decision_reason)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(music_file_id, ytm_upload_id) DO UPDATE SET
                    match_type=excluded.match_type,
                    match_score=excluded.match_score,
                    sync_decision=excluded.sync_decision,
                    decision_reason=excluded.decision_reason
                """,
                (file_id, ytm_upload_id, m_val, score, decision_val, decision_reason)
            )
            await db.commit()

    async def is_file_matched(self, music_file_id: int) -> bool:
        async with self.get_connection() as db:
            async with db.execute("SELECT 1 FROM matches WHERE music_file_id = ? LIMIT 1", (music_file_id,)) as cursor:
                return (await cursor.fetchone()) is not None

    async def clear_matches(self):
        async with self.get_connection() as db:
            await db.execute("DELETE FROM matches")
            await db.commit()

    async def get_local_filepath_for_upload(self, entity_id: str) -> Optional[str]:
        """Check if an upload entity is already matched to a local music file."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT mf.path 
                FROM matches m 
                JOIN music_files mf ON m.music_file_id = mf.id 
                WHERE m.ytm_upload_id = ? AND mf.path IS NOT NULL
                LIMIT 1
                """,
                (entity_id,)
            ) as cursor:
                row = await cursor.fetchone()
                return row[0] if row else None

    # Sync Jobs & Queue
    async def get_folder_song_counts(self, folder_path: str) -> dict:
        folder_prefix = folder_path.rstrip("/") + "/%"
        exact_match = folder_path.rstrip("/")
        async with self.get_connection() as db:
            db.row_factory = aiosqlite.Row
            # Total songs under this folder
            async with db.execute(
                "SELECT COUNT(*) as cnt FROM music_files WHERE path LIKE ? OR path = ?",
                (folder_prefix, exact_match)
            ) as cursor:
                row = await cursor.fetchone()
                total = row["cnt"] if row else 0

            # Unmapped songs (songs not yet matched/uploaded)
            async with db.execute(
                """
                SELECT COUNT(*) as cnt FROM music_files mf
                LEFT JOIN matches m ON mf.id = m.music_file_id
                WHERE (mf.path LIKE ? OR mf.path = ?) AND m.id IS NULL
                """,
                (folder_prefix, exact_match)
            ) as cursor:
                row = await cursor.fetchone()
                unmapped = row["cnt"] if row else 0

            return {"total": total, "unmapped": unmapped}

    async def record_file_replacement(
        self,
        original_path: str,
        original_sha256: str,
        original_size: int,
        original_mtime: float,
        replacement_source_id: str,
        replacement_path: Optional[str] = None,
        backup_path: Optional[str] = None
    ) -> int:
        """Record an audit trail entry for a replaced local audio file."""
        async with self.get_connection() as db:
            cursor = await db.execute(
                """
                INSERT INTO file_replacements (
                    original_path, original_sha256, original_size, original_mtime,
                    replacement_source_id, replacement_path, backup_path
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    original_path, original_sha256, original_size, original_mtime,
                    replacement_source_id, replacement_path, backup_path
                )
            )
            await db.commit()
            return cursor.lastrowid

    def record_file_replacement_sync(
        self,
        original_path: str,
        original_sha256: str,
        original_size: int,
        original_mtime: float,
        replacement_source_id: str,
        replacement_path: Optional[str] = None,
        backup_path: Optional[str] = None
    ):
        """Synchronously record an audit trail entry using direct sqlite3 connection."""
        import sqlite3
        with sqlite3.connect(str(self.db_path), timeout=30.0) as conn:
            conn.execute(
                """
                INSERT INTO file_replacements (
                    original_path, original_sha256, original_size, original_mtime,
                    replacement_source_id, replacement_path, backup_path
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    original_path, original_sha256, original_size, original_mtime,
                    replacement_source_id, replacement_path, backup_path
                )
            )
            conn.commit()

    async def get_file_replacements(self, limit: int = 100) -> list[dict]:
        """Fetch historical audit log of replaced local files."""
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM file_replacements ORDER BY replacement_timestamp DESC LIMIT ?",
                (limit,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]


