"""Router module for Library & Scanner endpoints."""
import logging

from pathlib import Path
from typing import Optional
import asyncio
import os
import shutil

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from ..models import MusicFile, ScanRequest
from ..database import db
from ..rate_limiter import rate_limit_dependency
from ..security import get_allowed_roots, validate_fs_path
from ..scanner import scanner
from ..scanner import write_metadata_tags
from ..matcher import matcher
from ..metadata_tracker import metadata_tracker

logger = logging.getLogger("ytm_sync")


def format_size(bytes_val: Optional[int | float]) -> str:
    """Format byte count as human-readable string."""
    if bytes_val is None or bytes_val < 0:
        return "N/A"
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:.1f} PiB"


router = APIRouter(tags=["Library & Scanner"])

@router.get("/api/fs/browse")
async def browse_filesystem(path: Optional[str] = Query(None)):
    """Browse directories inside approved container filesystem roots."""
    allowed_roots = get_allowed_roots()
    if not allowed_roots:
        raise HTTPException(status_code=500, detail="No approved filesystem roots configured")

    if not path:
        target_path = next((r for r in allowed_roots if r.exists()), allowed_roots[0])
    else:
        try:
            target_path = validate_fs_path(path, must_exist=True)
        except ValueError as e:
            raise HTTPException(status_code=403, detail=str(e))

    if not target_path.is_dir():
        raise HTTPException(status_code=400, detail="Requested path is not a directory")

    directories = []
    try:
        for entry in os.scandir(str(target_path)):
            try:
                if entry.is_dir(follow_symlinks=True):
                    entry_p = Path(entry.path)
                    try:
                        validate_fs_path(entry_p, must_exist=True)
                        directories.append({
                            "name": entry.name,
                            "path": str(entry_p)
                        })
                    except ValueError:
                        continue
            except (PermissionError, OSError):
                continue
    except (PermissionError, OSError):
        pass

    directories.sort(key=lambda x: x["name"].lower())

    parent_path = None
    if target_path != target_path.parent:
        try:
            parent_resolved = validate_fs_path(target_path.parent, must_exist=True)
            parent_path = str(parent_resolved)
        except ValueError:
            parent_path = None

    free_space = "N/A"
    total_space = "N/A"
    try:
        usage = shutil.disk_usage(str(target_path))
        free_space = format_size(usage.free)
        total_space = format_size(usage.total)
    except Exception:
        pass

    return {
        "current_path": str(target_path),
        "parent_path": parent_path,
        "directories": directories,
        "free_space": free_space,
        "total_space": total_space,
        "allowed_roots": [str(r) for r in allowed_roots]
    }


@router.get("/api/folders")
async def get_folders() -> list[str]:
    folders = await db.get_setting("music_folders", default=[])
    return folders


@router.get("/api/folders/stats")
async def get_folders_stats():
    """Get root folder statistics including free space, songs count, and unmapped count."""
    folders = await db.get_setting("music_folders", default=[])
    results = []
    for f in folders:
        p = Path(f)
        free_space = "N/A"
        total_space = "N/A"
        exists = p.exists() and p.is_dir()
        if exists:
            try:
                usage = shutil.disk_usage(str(p))
                free_space = format_size(usage.free)
                total_space = format_size(usage.total)
            except Exception:
                pass

        counts = await db.get_folder_song_counts(f)
        results.append({
            "path": f,
            "exists": exists,
            "free_space": free_space,
            "total_space": total_space,
            "songs_count": counts["total"],
            "unmapped_count": counts["unmapped"]
        })
    return results


class FoldersUpdate(BaseModel):
    folders: list[str] = Field(..., min_length=1, max_length=50, description="Music folders allowlist (max 50)")

@router.post("/api/folders")
async def update_folders(req: FoldersUpdate):
    safe_folders = []
    for f in req.folders:
        try:
            p = validate_fs_path(f, must_exist=False)
            safe_folders.append(str(p))
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid folder path '{f}': {e}")
    await db.set_setting("music_folders", safe_folders)
    return {"status": "success", "folders": safe_folders}


@router.post("/api/scan", dependencies=[Depends(rate_limit_dependency(10, 60, "scan", use_user_id=True))])
async def trigger_scan(bg_tasks: BackgroundTasks, req: Optional[ScanRequest] = None):
    if scanner.is_scanning:
        return {"status": "in_progress", "message": "Scan is already running"}

    raw_folders = req.folders if req and req.folders else await db.get_setting("music_folders", default=[])
    if not raw_folders:
        raise HTTPException(status_code=400, detail="No music folders configured to scan")

    folders = []
    for f in raw_folders:
        try:
            p = validate_fs_path(f, must_exist=True)
            folders.append(str(p))
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid scan folder '{f}': {e}")

    async def _run_scan_and_match():
        await scanner.scan_folders(folders)
        # Re-run matching automatically after scanning
        await matcher.match_all()

    bg_tasks.add_task(_run_scan_and_match)
    return {"status": "started", "message": "Scan started in background", "folders": folders}


@router.get("/api/songs")
async def get_songs(
    status: Optional[str] = Query(None, description="Filter: all, missing, uploaded, failed, queued"),
    search: Optional[str] = Query(None, description="Search query across title, artist, album"),
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0)
) -> list[MusicFile]:
    return await db.get_music_files(filter_status=status, search=search, limit=limit, offset=offset)


class MetadataUpdateRequest(BaseModel):
    title: str
    artist: Optional[str] = None
    album: Optional[str] = None
    track_number: Optional[int] = None
    cover_url: Optional[str] = None

@router.post("/api/songs/{file_id}/metadata", response_model=MusicFile)
async def update_song_metadata(file_id: int, req: MetadataUpdateRequest):
    """Update title, artist, album, track_number for a local song and write to file if writable."""
    try:
        existing = await db.get_music_file_by_id(file_id)
        if not existing:
            raise HTTPException(status_code=404, detail=f"Music file with ID {file_id} not found")

        updated = await db.update_music_file_metadata(
            file_id=file_id,
            title=req.title.strip(),
            artist=req.artist.strip() if req.artist else None,
            album=req.album.strip() if req.album else None,
            track_number=req.track_number
        )
        if not updated:
            raise HTTPException(status_code=500, detail="Failed to update music file metadata in database")

        from ..scanner import write_metadata_tags
        tags_written = False
        target_path = Path(existing.path)
        is_writable = False
        try:
            is_writable = target_path.exists() and os.access(target_path, os.W_OK)
        except Exception:
            is_writable = False

        if is_writable:
            try:
                await asyncio.to_thread(
                    write_metadata_tags,
                    target_path,
                    title=req.title.strip(),
                    artist=req.artist.strip() if req.artist else None,
                    album=req.album.strip() if req.album else None,
                    track_number=req.track_number,
                    cover_url=req.cover_url
                )
                tags_written = True
            except (PermissionError, OSError) as e:
                logger.warning(f"File system is read-only; tags not written to {existing.path}: {e}")
            except Exception as e:
                logger.warning(f"Could not write tags directly to file {existing.path}: {e}")
        else:
            logger.info(f"Skipping direct tag modification for read-only file: {existing.path}")

        # Re-evaluate matching for this file
        try:
            await matcher.match_single_file(updated)
        except Exception as e:
            logger.warning(f"Matching re-evaluation failed: {e}")

        refreshed = await db.get_music_file_by_id(file_id)
        final_obj = refreshed or updated
        detail_msg = "Updated ID3 tags & metadata on disk" if tags_written else "Updated metadata in database (local file is read-only; tags untouched)"
        metadata_tracker.log_change(
            title=final_obj.title or req.title,
            artist=final_obj.artist,
            album=final_obj.album,
            thumbnail=req.cover_url,
            source="Local Song Metadata Editor",
            detail=detail_msg
        )
        return final_obj
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Unhandled error in update_song_metadata: {e}")
        raise HTTPException(status_code=500, detail=f"Error updating metadata: {str(e)}")


class BatchDeleteSongsRequest(BaseModel):
    file_ids: list[int] = Field(..., min_length=1, max_length=500, description="List of song IDs to delete (max 500)")

@router.post("/api/songs/batch-delete")
async def batch_delete_songs(req: BatchDeleteSongsRequest):
    deleted = 0
    async with db.get_connection() as conn:
        for fid in req.file_ids:
            await conn.execute("DELETE FROM matches WHERE music_file_id = ?", (fid,))
            await conn.execute("DELETE FROM sync_jobs WHERE music_file_id = ?", (fid,))
            await conn.execute("DELETE FROM music_files WHERE id = ?", (fid,))
            deleted += 1
        await conn.commit()
    return {"status": "success", "deleted": deleted}


@router.get("/api/songs/{file_id}/artwork")
async def get_song_artwork(file_id: int):
    """Serve embedded cover art from a local music file."""
    file = await db.get_music_file_by_id(file_id)
    if not file:
        raise HTTPException(status_code=404, detail="Song not found")
    from ..scanner import extract_artwork
    res = await asyncio.to_thread(extract_artwork, Path(file.path))
    if not res:
        raise HTTPException(status_code=404, detail="No embedded artwork found")
    data, mime = res
    from fastapi.responses import Response
    return Response(
        content=data,
        media_type=mime,
        headers={"Cache-Control": "public, max-age=86400, immutable"}
    )


