"""Router module for Recovery & Utilities endpoints."""
import logging

from .. import __version__

from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

from ..models import (
    SyncJob,
    MusicBrainzMatch,
    User,
    UserRole,
    TrackDestinationDuplicateStatus
)
from ..database import db
from ..config import settings
from ..dependencies import get_optional_authenticated_user, require_authenticated_user
from ..security import validate_fs_path
from ..musicbrainz import musicbrainz_client
from ..downloader import download_upload, commit_staged_file_to_destination
from ..recovery import audit_and_flag_suspicious_files, restore_corrupted_file

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Recovery & Utilities"])

@router.get("/api/tracks/{file_id}/destinations-status", response_model=list[TrackDestinationDuplicateStatus])
async def get_track_destinations_status(file_id: int, current_user: User = Depends(require_authenticated_user)):
    """Check duplicate and upload status per destination account (Section 34)."""
    accounts = await db.get_permitted_family_accounts(current_user.id)
    results = []
    for acc in accounts:
        dest_uid = acc["user_id"]
        dup_info = await db.check_track_duplicate_for_user(file_id, dest_uid)
        results.append(TrackDestinationDuplicateStatus(
            destination_user_id=dest_uid,
            destination_username=acc["username"],
            is_uploaded=dup_info["is_uploaded"],
            status=dup_info["status"],
            error=dup_info.get("error")
        ))
    return results


@router.get("/api/history")
async def get_history(limit: int = 100, current_user: Optional[User] = Depends(get_optional_authenticated_user)) -> list[SyncJob]:
    if current_user and current_user.role != UserRole.ADMIN:
        return await db.get_user_sync_history(user_id=current_user.id, limit=limit)
    return await db.get_sync_history(limit=limit)


@router.get("/api/logs")
async def get_recent_logs(lines: int = Query(100, ge=1, le=1000)) -> list[str]:
    log_file = settings.log_file
    if not log_file.exists():
        return []
    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
        all_lines = f.readlines()
        return [l.rstrip("\r\n") for l in all_lines[-lines:]]


class FileReplacePreviewRequest(BaseModel):
    music_file_id: Optional[int] = None
    local_path: Optional[str] = None
    upload_entity_id: Optional[str] = None
    upload_video_id: Optional[str] = None

class FileReplaceExecuteRequest(BaseModel):
    music_file_id: Optional[int] = None
    local_path: Optional[str] = None
    upload_entity_id: Optional[str] = None
    upload_video_id: Optional[str] = None
    confirm: bool = False

@router.post("/api/files/replace/preview")
async def preview_file_replacement(req: FileReplacePreviewRequest):
    local_p: Optional[Path] = None
    local_mf = None
    if req.music_file_id:
        local_mf = await db.get_music_file_by_id(req.music_file_id)
        if local_mf:
            local_p = Path(local_mf.path)
    elif req.local_path:
        local_p = Path(req.local_path)

    if not local_p or not local_p.exists():
        raise HTTPException(status_code=404, detail=f"Local music file not found: {req.local_path or req.music_file_id}")

    upload = None
    if req.upload_entity_id:
        upload = await db.get_ytm_upload_by_entity_id(req.upload_entity_id)
    elif req.upload_video_id:
        upload = await db.get_ytm_upload_by_video_id(req.upload_video_id)

    if not upload:
        raise HTTPException(status_code=404, detail="Upload record not found")

    import hashlib
    h = hashlib.sha256()
    with open(local_p, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    local_sha256 = h.hexdigest()
    local_size = local_p.stat().st_size
    local_duration = local_mf.duration if local_mf else None

    upload_id = upload.video_id or upload.upload_video_id or upload.entity_id
    id_matches = bool(upload_id and len(upload_id) >= 11)
    duration_matches = True
    if local_duration and upload.duration:
        duration_matches = abs(local_duration - upload.duration) <= 4.0

    return {
        "local_file": {
            "path": str(local_p),
            "sha256": local_sha256,
            "size": local_size,
            "duration": local_duration
        },
        "new_source": {
            "source_type": "ytm_upload",
            "upload_id": upload_id,
            "title": upload.title,
            "artist": upload.artist,
            "expected_duration": upload.duration
        },
        "verification": {
            "upload_id_matches": id_matches,
            "duration_matches": duration_matches,
            "audio_validation_passed": id_matches and duration_matches,
            "status": "PASS" if (id_matches and duration_matches) else "REVIEW_REQUIRED"
        },
        "settings": {
            "automatic_replacement_enabled": settings.allow_automatic_replacement,
            "manual_confirmation_required": True
        }
    }


@router.post("/api/files/replace/execute")
async def execute_manual_file_replacement(req: FileReplaceExecuteRequest):
    if not req.confirm:
        raise HTTPException(
            status_code=400,
            detail="Explicit confirmation (confirm=true) is required to replace an existing local file."
        )

    local_p: Optional[Path] = None
    if req.music_file_id:
        mf = await db.get_music_file_by_id(req.music_file_id)
        if mf:
            local_p = Path(mf.path)
    elif req.local_path:
        local_p = Path(req.local_path)

    if not local_p or not local_p.exists():
        raise HTTPException(status_code=404, detail="Local music file not found on disk")

    upload = None
    if req.upload_entity_id:
        upload = await db.get_ytm_upload_by_entity_id(req.upload_entity_id)
    elif req.upload_video_id:
        upload = await db.get_ytm_upload_by_video_id(req.upload_video_id)

    if not upload:
        raise HTTPException(status_code=404, detail="Upload record not found")

    upload_id = upload.video_id or upload.upload_video_id or upload.entity_id

    staged = await download_upload(upload)

    try:
        committed_file = commit_staged_file_to_destination(
            staged_file=staged,
            destination_file=local_p,
            allow_overwrite=True,
            replacement_source_id=upload_id,
            authorized_manual_action=True
        )
    except Exception as ex:
        logger.error(f"Manual replacement failed: {ex}")
        raise HTTPException(status_code=500, detail=str(ex))
    finally:
        if staged.exists():
            try:
                staged.unlink()
            except Exception:
                pass

    return {
        "status": "success",
        "message": f"Successfully replaced {committed_file.name} with verified upload {upload_id}",
        "destination_file": str(committed_file),
        "source_id": upload_id
    }


class RestoreFileRequest(BaseModel):
    path: str

@router.get("/api/recovery/suspicious-files")
async def get_suspicious_files():
    from ..recovery import audit_and_flag_suspicious_files
    files = await audit_and_flag_suspicious_files(database=db)
    return {"suspicious_files": files, "count": len(files)}


@router.post("/api/recovery/audit")
async def run_recovery_audit():
    from ..recovery import audit_and_flag_suspicious_files
    files = await audit_and_flag_suspicious_files(database=db)
    return {"status": "success", "flagged_count": len(files), "flagged_files": files}


@router.post("/api/recovery/restore")
async def restore_suspicious_file(req: RestoreFileRequest):
    from ..recovery import restore_corrupted_file
    try:
        res = await restore_corrupted_file(req.path, database=db)
        return res
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to restore file: {str(e)}")


@router.get("/health")
async def health_check():
    return {"status": "healthy", "version": __version__}


@router.get("/api/musicbrainz/search", response_model=list[MusicBrainzMatch])
async def search_musicbrainz(
    query: Optional[str] = Query(None, description="Free-text search query"),
    artist: Optional[str] = Query(None, description="Artist name"),
    title: Optional[str] = Query(None, description="Song title"),
    provider: Optional[str] = Query("all", description="Metadata provider: all, ytm, deezer, itunes, musicbrainz"),
    limit: int = Query(6, ge=1, le=12, description="Max results")
):
    try:
        matches = await musicbrainz_client.search(
            query=query,
            artist=artist,
            title=title,
            provider=provider,
            limit=limit
        )
        return matches
    except Exception as e:
        logger.error(f"Error in musicbrainz search endpoint: {e}", exc_info=True)
        return []


@router.post("/api/database/backup")
async def backup_db():
    backup_path = await db.backup_database()
    return {"status": "success", "backup_path": backup_path}


@router.get("/api/metadata/cover-art")
async def get_cover_art_url(
    artist: str = Query(...),
    title: Optional[str] = Query(None),
    album: Optional[str] = Query(None),
):
    """Fetch high-res album artwork URL for a track or album."""
    url = await musicbrainz_client.fetch_cover_art_url(artist=artist, title=title, album=album)
    return {"cover_url": url}


@router.get("/api/artwork/{filename}")
async def get_artwork_file(filename: str):
    """Serve custom uploaded artwork images."""
    from fastapi.responses import FileResponse
    art_dir = (settings.data_dir / "artwork").resolve()
    try:
        art_file = validate_fs_path(art_dir / filename, allowed_roots=[art_dir], must_exist=True)
    except ValueError:
        raise HTTPException(status_code=404, detail="Artwork file not found")
    if not art_file.is_file():
        raise HTTPException(status_code=404, detail="Artwork file not found")
    return FileResponse(art_file)


