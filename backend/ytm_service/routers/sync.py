"""Router module for Sync & Uploads endpoints."""
import logging

from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from ..models import (
    YtmUpload,
    SyncJob,
    User,
    UserRole,
    UploadDestinationRequest,
    UploadDestinationResponse
)
from ..database import db
from ..dependencies import get_optional_authenticated_user, require_authenticated_user
from ..security import validate_fs_path
from ..ytm_client import ytm_client
from ..matcher import matcher
from ..uploader import queue_manager
from ..playlist_downloader import download_and_upload_playlist_track
from ..queue_service import unified_queue_service
from ..metadata_tracker import metadata_tracker

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Sync & Uploads"])

@router.post("/api/uploads/destinations", response_model=UploadDestinationResponse)
async def upload_to_destinations(req: UploadDestinationRequest, current_user: User = Depends(require_authenticated_user)):
    """Create independent upload jobs per selected destination account with strict validation (Sections 11, 12, 15, 24)."""
    if not req.music_file_ids:
        raise HTTPException(status_code=400, detail="No files provided for upload")
    if not req.destination_user_ids:
        raise HTTPException(status_code=400, detail="No destination accounts selected")

    created_job_ids = []
    errors = []

    for dest_id in req.destination_user_ids:
        allowed, reason = await db.validate_upload_destination_permission(current_user.id, dest_id)
        if not allowed:
            dest_user = await db.get_user_by_id(dest_id)
            name = dest_user.username if dest_user else dest_id
            errors.append(f"{name}: {reason}")
            continue

        dest_acc = await db.get_ytm_account(dest_id)
        acc_id = dest_acc.id if dest_acc else None

        for fid in req.music_file_ids:
            try:
                job_id = await db.create_sync_job(
                    music_file_id=fid,
                    user_id=dest_id,
                    destination_user_id=dest_id,
                    requested_by_user_id=current_user.id,
                    family_id=req.family_id,
                    youtube_music_account_id=acc_id
                )
                created_job_ids.append(job_id)
            except Exception as e:
                errors.append(f"File {fid} for user {dest_id}: {str(e)}")

    if not created_job_ids and errors:
        is_forbidden = any("not in your family" in err or "disabled family uploads" in err for err in errors)
        raise HTTPException(status_code=403 if is_forbidden else 400, detail="; ".join(errors))

    return UploadDestinationResponse(
        jobs_created=len(created_job_ids),
        job_ids=created_job_ids,
        errors=errors
    )


@router.post("/api/sync")
async def sync_remote_and_match(bg_tasks: BackgroundTasks):
    """Fetch remote YTM uploads and run local comparison matching."""
    async def _run_sync():
        try:
            logger.info("Fetching remote YouTube Music uploads...")
            await ytm_client.fetch_and_cache_uploads()
            logger.info("Running matching engine...")
            await matcher.match_all()
        except Exception as e:
            logger.error(f"Sync failed: {e}")

    bg_tasks.add_task(_run_sync)
    return {"status": "started", "message": "Library synchronization started"}


class BatchUploadRequest(BaseModel):
    file_ids: list[int] = Field(..., min_length=1, max_length=500, description="List of file IDs to enqueue (max 500)")

@router.post("/api/upload/batch")
async def upload_batch(req: BatchUploadRequest):
    enqueued = 0
    for fid in req.file_ids:
        try:
            await queue_manager.enqueue_song(fid)
            enqueued += 1
        except Exception as e:
            logger.warning(f"Failed to enqueue song {fid}: {e}")
    return {"status": "enqueued", "enqueued_count": enqueued}


@router.post("/api/upload/all-missing")
async def upload_all_missing():
    count = await queue_manager.enqueue_all_missing()
    return {"status": "enqueued", "enqueued_count": count}


@router.post("/api/upload/{file_id}")
async def upload_single(file_id: int):
    file = await db.get_music_file_by_id(file_id)
    if not file:
        raise HTTPException(status_code=404, detail="Music file not found")
    job_id = await queue_manager.enqueue_song(file_id)
    return {"status": "enqueued", "job_id": job_id, "filename": file.filename}


@router.get("/api/queue")
async def get_unified_queue(
    category: str = Query("all", description="all, metadata_change, download, upload, local_upload"),
    status: str = Query("all", description="all, active, completed, failed"),
    limit: int = Query(200, ge=1, le=1000)
):
    """Fetch unified queue aggregating playlist downloads, cloud locker uploads, local uploads, and metadata changes."""
    return await unified_queue_service.get_queue(category=category, status=status, limit=limit)


@router.post("/api/queue/clear-completed")
async def clear_completed_queue():
    """Clear completed and failed items from queue history."""
    unified_queue_service.clear_completed()
    return {"status": "ok"}


@router.post("/api/queue/cancel-all")
async def cancel_all_queue():
    """Cancel any active playlist sync and clear queued local jobs."""
    await unified_queue_service.cancel_all()
    return {"status": "ok"}


@router.post("/api/queue/jobs/{job_id}/retry-blocked")
async def retry_blocked_queue_job(job_id: int):
    """
    Manually retry a BLOCKED job (Blocker 3).
    Guarantees that retry can only occur with the original upload source ID,
    never converting into a catalog search.
    """
    try:
        updated_job = await db.retry_blocked_sync_job(job_id)
        if not updated_job:
            raise HTTPException(status_code=404, detail="Job not found")
        return {
            "status": "success",
            "message": f"Job {job_id} re-queued for original upload source",
            "job": updated_job
        }
    except ValueError as ex:
        raise HTTPException(status_code=400, detail=str(ex))
    except FileNotFoundError as ex:
        raise HTTPException(status_code=404, detail=str(ex))


class ResolveNeedsHelpRequest(BaseModel):
    title: str
    artist: Optional[str] = None
    album: Optional[str] = None
    thumbnail: Optional[str] = None
    destination_dir: Optional[str] = None

@router.get("/api/needs-help")
async def get_needs_help_tracks():
    """List all tracks skipped during download because metadata match was missing."""
    return await db.get_needs_help_tracks()


@router.delete("/api/needs-help/{video_id}")
async def dismiss_needs_help_track(video_id: str):
    """Dismiss a track from needs-help list."""
    await db.delete_needs_help_track(video_id)
    return {"status": "ok"}


@router.post("/api/needs-help/{video_id}/resolve")
async def resolve_needs_help_track(video_id: str, req: ResolveNeedsHelpRequest):
    """Resolve a needs-help track with user-selected metadata, download, and upload."""
    dest_path = None
    if req.destination_dir:
        try:
            dest_path = validate_fs_path(req.destination_dir, allow_create_in_parent=True)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid destination_dir: {e}")

    res = await download_and_upload_playlist_track(
        video_id=video_id,
        raw_title=req.title,
        raw_artist=req.artist,
        raw_album=req.album,
        raw_thumbnail=req.thumbnail,
        destination_dir=dest_path,
        enrich_metadata=False,
        require_full_match=False
    )
    if res.get("status") == "success":
        await db.delete_needs_help_track(video_id)
        metadata_tracker.log_change(
            title=res.get("title") or req.title,
            artist=res.get("artist") or req.artist,
            album=res.get("album") or req.album,
            thumbnail=res.get("cover_url") or req.thumbnail,
            source="Needs Help Matcher",
            detail="Resolved metadata & uploaded to YouTube Music locker"
        )
    return res


@router.get("/api/uploads", response_model=list[YtmUpload])
async def get_uploads(current_user: Optional[User] = Depends(get_optional_authenticated_user)) -> list[YtmUpload]:
    if current_user and current_user.role != UserRole.ADMIN:
        return await db.get_all_ytm_uploads(user_id=current_user.id)
    return await db.get_all_ytm_uploads()


@router.get("/api/jobs/{job_id}", response_model=SyncJob)
async def get_job_by_id(job_id: int, current_user: Optional[User] = Depends(get_optional_authenticated_user)) -> SyncJob:
    job = await db.get_sync_job_by_id(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Sync job not found")
    if current_user and current_user.role != UserRole.ADMIN:
        if job.user_id and job.user_id != current_user.id:
            raise HTTPException(status_code=404, detail="Sync job not found")
    return job


