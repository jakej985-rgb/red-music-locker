"""Router module for YouTube Music endpoints."""
import logging

from pathlib import Path
from typing import Optional
import asyncio
import shutil

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from ..models import (
    PlaylistTrackDownloadRequest,
    PlaylistImportRequest,
    User,
    YouTubeMusicAccountResponse,
    PlaylistSyncMissingRequest
)
from ..database import db
from ..config import settings
from ..dependencies import require_authenticated_user
from ..security import validate_fs_path, validate_youtube_url
from ..scanner import write_metadata_tags
from ..ytm_client import ytm_client
from ..auth_service import auth_service
from ..playlist_downloader import playlist_sync_manager
from ..playlist_downloader import download_and_upload_playlist_track
from ..metadata_tracker import metadata_tracker
from ..downloader import download_ytm_upload, extract_playlist_info
from .library import MetadataUpdateRequest

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["YouTube Music"])

@router.get("/api/ytm/account", response_model=Optional[YouTubeMusicAccountResponse])
async def get_ytm_account(current_user: User = Depends(require_authenticated_user)):
    """Get linked YouTube Music account for current user."""
    account = await db.get_ytm_account_by_user_id(current_user.id)
    if not account:
        return None
    return YouTubeMusicAccountResponse(
        id=account.id,
        user_id=account.user_id,
        account_name=account.account_name,
        account_identifier=account.account_identifier,
        status=account.status,
        created_at=account.created_at,
        updated_at=account.updated_at,
        last_verified_at=account.last_verified_at,
    )


@router.post("/api/ytm/disconnect")
async def disconnect_ytm_account(current_user: User = Depends(require_authenticated_user)):
    """Disconnect linked YouTube Music account for current user."""
    res = await auth_service.disconnect(user_id=current_user.id)
    return res


@router.get("/api/ytm/playlists")
async def get_ytm_playlists(user_id: Optional[str] = None, current_user: User = Depends(require_authenticated_user)):
    target_uid = user_id or current_user.id
    if target_uid != current_user.id:
        permitted_accounts = await db.get_permitted_family_accounts(current_user.id)
        permitted = any(a.get("user_id") == target_uid and a.get("allow_family_playlists") for a in permitted_accounts)
        if not permitted:
            raise HTTPException(status_code=403, detail="Access to this family member's playlists is not permitted")

    if not ytm_client.is_auth_configured(user_id=target_uid):
        raise HTTPException(status_code=400, detail="YouTube Music not authenticated for this account")
    try:
        playlists = await ytm_client.get_playlists(user_id=target_uid)
        return playlists
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch playlists: {e}")


@router.get("/api/ytm/playlists/sync-status")
async def get_playlist_sync_status():
    """Get active playlist download/sync progress."""
    return playlist_sync_manager.status


@router.post("/api/ytm/playlists/cancel-sync")
async def cancel_playlist_sync():
    """Cancel any active background playlist download/sync."""
    return playlist_sync_manager.cancel_sync()


@router.post("/api/ytm/playlists/download-track")
async def download_playlist_track_endpoint(
    req: PlaylistTrackDownloadRequest,
    current_user: User = Depends(require_authenticated_user),
):
    """Download, tag, and upload a single playlist track to YouTube Music locker."""
    dest_path = None
    if req.destination_dir:
        try:
            dest_path = validate_fs_path(req.destination_dir, allow_create_in_parent=True)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid destination_dir: {e}")

    if not ytm_client.is_auth_configured(user_id=current_user.id):
        raise HTTPException(status_code=400, detail="YouTube Music not authenticated")
    try:
        res = await download_and_upload_playlist_track(
            video_id=req.video_id,
            raw_title=req.title,
            raw_artist=req.artist,
            raw_album=req.album,
            raw_thumbnail=req.thumbnail,
            destination_dir=dest_path,
            enrich_metadata=req.enrich_metadata
        )
        return res
    except Exception as e:
        logger.exception(f"Failed to download and upload track {req.video_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to download and upload track: {e}")


@router.post("/api/ytm/playlists/import-url")
async def import_playlist_url_endpoint(
    req: PlaylistImportRequest,
    current_user: User = Depends(require_authenticated_user),
):
    """Import and audit an external YouTube / YouTube Music playlist URL."""
    try:
        validate_youtube_url(req.url)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid playlist URL: {e}")
    try:
        raw_info = await extract_playlist_info(req.url)
        tracks_raw = raw_info.get("tracks", [])

        # Match against local files and locker uploads
        local_files = await db.get_all_local_songs()
        uploads = await db.get_all_ytm_uploads()

        from ..normalizer import normalize_text

        local_map = {}
        for f in local_files:
            key = f"{normalize_text(f.get('artist'))}|{normalize_text(f.get('title'))}"
            local_map[key] = f.get("path")
            title_key = normalize_text(f.get("title"))
            if title_key and title_key not in local_map:
                local_map[title_key] = f.get("path")

        uploads_set = set()
        for u in uploads:
            u_key = f"{normalize_text(u.artist)}|{normalize_text(u.title)}"
            uploads_set.add(u_key)
            u_title = normalize_text(u.title)
            if u_title:
                uploads_set.add(u_title)

        matched_tracks = []
        for t in tracks_raw:
            title = t.get("title", "")
            artist = t.get("artist")
            key = f"{normalize_text(artist)}|{normalize_text(title)}"
            title_k = normalize_text(title)

            in_local = key in local_map or title_k in local_map
            local_path = local_map.get(key) or local_map.get(title_k)
            in_uploads = key in uploads_set or title_k in uploads_set

            matched_tracks.append({
                **t,
                "in_local": in_local,
                "local_path": local_path,
                "in_uploads": in_uploads
            })

        return {
            **raw_info,
            "tracks": matched_tracks
        }
    except Exception as e:
        logger.exception(f"Failed to import playlist from URL {req.url}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to import playlist: {e}")


@router.get("/api/ytm/playlists/{playlist_id}")
async def get_ytm_playlist_details(
    playlist_id: str,
    refresh: bool = False,
    current_user: User = Depends(require_authenticated_user),
):
    if not ytm_client.is_auth_configured(user_id=current_user.id):
        raise HTTPException(status_code=400, detail="YouTube Music not authenticated")
    try:
        if refresh:
            try:
                await ytm_client.fetch_and_cache_uploads(user_id=current_user.id)
            except Exception as ex:
                logger.warning(f"Failed to refresh uploads from YTM: {ex}")
        details = await ytm_client.get_playlist_details(playlist_id, user_id=current_user.id)
        return details
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch playlist details: {e}")


@router.post("/api/ytm/playlists/{playlist_id}/sync-missing")
async def sync_missing_playlist_tracks(
    playlist_id: str,
    destination_dir: Optional[str] = None,
    body: Optional[PlaylistSyncMissingRequest] = None,
    current_user: User = Depends(require_authenticated_user),
):
    """Start background sync for tracks in a playlist missing from uploads (supports multi-account destination)."""
    dest_path = None
    target_dir = (body.destination_dir if body and body.destination_dir else destination_dir)
    if target_dir:
        try:
            dest_path = str(validate_fs_path(target_dir, allow_create_in_parent=True))
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid destination_dir: {e}")

    if not ytm_client.is_auth_configured(user_id=current_user.id):
        raise HTTPException(status_code=400, detail="YouTube Music not authenticated")

    try:
        details = await ytm_client.get_playlist_details(playlist_id, user_id=current_user.id)
        tracks = details.get("tracks", [])

        # Validate destination user IDs
        raw_target_uids = (body.destination_user_ids if body and body.destination_user_ids else [current_user.id])
        target_uids = []
        permitted_accounts = await db.get_permitted_family_accounts(current_user.id)
        permitted_lookup = {a.get("user_id"): a for a in permitted_accounts}

        for uid in raw_target_uids:
            if uid == current_user.id:
                target_uids.append(uid)
            else:
                acc = permitted_lookup.get(uid)
                if acc and (acc.get("allow_family_uploads") or acc.get("allow_family_sync")):
                    target_uids.append(uid)

        if not target_uids:
            target_uids = [current_user.id]

        # Check which tracks are missing from ANY of the target users' lockers
        missing = []
        for t in tracks:
            if t.get("is_duplicate"):
                continue
            vid = t.get("video_id")
            tit = t.get("title")
            art = t.get("artist")
            is_missing = False
            for uid in target_uids:
                if uid == current_user.id and t.get("in_uploads"):
                    has_it = True
                else:
                    has_it = await db.get_ytm_upload_by_video_id(vid, user_id=uid) or await db.find_ytm_upload_by_title_artist(tit, art, user_id=uid)
                if not has_it:
                    is_missing = True
                    break
            if is_missing:
                missing.append(t)

        if not missing:
            return {"status": "ok", "message": "All tracks in this playlist are already in the cloud uploads of the selected accounts!", "queued": 0}

        status = playlist_sync_manager.start_sync(
            playlist_id=playlist_id,
            playlist_title=details.get("title", "Playlist"),
            tracks_to_sync=missing,
            destination_dir=dest_path,
            destination_user_ids=target_uids
        )
        return {
            "status": "started",
            "message": f"Started syncing {len(missing)} missing tracks from '{details.get('title')}' to {len(target_uids)} account(s)",
            "queued": len(missing),
            "target_user_ids": target_uids,
            "sync_status": status
        }
    except RuntimeError as re:
        raise HTTPException(status_code=409, detail=str(re))
    except Exception as e:
        logger.exception(f"Failed to sync missing playlist tracks: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to start playlist sync: {e}")


# ============================================================================
# Replicated Playlists (1:1 Locker-Only Replica Engine)
# ============================================================================


@router.get("/api/ytm/uploads/summary")
async def get_ytm_uploads_summary():
    """Get summary counts of YTM uploads (total, missing metadata, properly tagged)."""
    return await db.get_ytm_uploads_summary()


@router.get("/api/ytm/uploads")
async def get_ytm_uploads(
    filter_type: str = Query("all", description="Filter: all, missing_metadata, proper"),
    search: Optional[str] = Query(None, description="Search query"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200)
):
    """List YouTube Music uploads from DB with pagination, search, and health filters."""
    return await db.get_ytm_uploads(filter_type=filter_type, search=search, page=page, page_size=page_size)


@router.post("/api/ytm/uploads/{entity_id}/replace")
async def replace_ytm_upload(entity_id: str, req: MetadataUpdateRequest):
    """Download untagged upload from YTM, tag with new metadata, upload new version, and delete old upload."""
    upload = await db.get_ytm_upload_by_entity_id(entity_id)
    if not upload:
        raise HTTPException(status_code=404, detail="Upload entity not found in database.")
    if not upload.video_id:
        raise HTTPException(status_code=400, detail="Upload does not have an associated video ID for streaming.")

    downloaded_path: Optional[Path] = None
    try:
        staging_dir = settings.data_dir / "staging"
        staging_dir.mkdir(parents=True, exist_ok=True)
        target_staging = staging_dir / f"ytm_{upload.video_id}_clean.mp3"

        # Phase 0: Check if this file already exists locally in DB matches, music_files, or /music
        local_fp = await db.get_local_filepath_for_upload(entity_id)
        if not local_fp:
            async with db.get_connection() as conn:
                clean_name = upload.title.strip()
                stem = Path(clean_name).stem
                async with conn.execute(
                    "SELECT path FROM music_files WHERE filename = ? OR filename = ? OR title = ? LIMIT 1",
                    (clean_name, f"{stem}.mp3", clean_name)
                ) as cursor:
                    row = await cursor.fetchone()
                    if row:
                        local_fp = row[0]

        if local_fp:
            try:
                safe_local = validate_fs_path(local_fp, must_exist=True)
                logger.info(f"Found local file for upload {entity_id} via library: {safe_local}")
                shutil.copy2(safe_local, target_staging)
                downloaded_path = target_staging
            except Exception as e:
                logger.warning(f"Local file {local_fp} failed path validation: {e}")

        if not downloaded_path and Path("/music").is_dir():
            clean_name = upload.title.strip()
            stem = Path(clean_name).stem
            candidates = list(Path("/music").rglob(f"{clean_name}*"))
            if not candidates:
                candidates = list(Path("/music").rglob(f"{stem}.*"))
            valid = [c for c in candidates if c.is_file()]
            if valid:
                try:
                    safe_candidate = validate_fs_path(valid[0], must_exist=True)
                    logger.info(f"Found local file for upload {entity_id} in /music: {safe_candidate}")
                    shutil.copy2(safe_candidate, target_staging)
                    downloaded_path = target_staging
                except Exception as e:
                    logger.warning(f"Candidate file {valid[0]} failed path validation: {e}")

        # 1. Download audio file from YTM upload locker (strictly exact upload identity; NO search fallback)
        if not downloaded_path:
            logger.info(f"Phase 1: Downloading untagged upload {entity_id} (video: {upload.video_id})")
            downloaded_path = await download_ytm_upload(upload.video_id)

        # 2. Write new metadata tags using Mutagen
        logger.info(f"Phase 2: Tagging audio with Title='{req.title}', Artist='{req.artist}', Album='{req.album}', CoverURL='{req.cover_url}'")
        await asyncio.to_thread(
            write_metadata_tags,
            downloaded_path,
            title=req.title.strip(),
            artist=req.artist.strip() if req.artist else None,
            album=req.album.strip() if req.album else None,
            track_number=req.track_number,
            cover_url=req.cover_url
        )

        # 3. Upload new tagged version to YouTube Music
        logger.info(f"Phase 3: Uploading newly tagged file {downloaded_path.name} to YTM")
        up_res = await ytm_client.upload_file(str(downloaded_path))
        if not up_res.get("success"):
            raise HTTPException(status_code=500, detail=f"Upload failed: {up_res.get('response')}")

        # 4. Delete old untagged upload from YouTube Music
        logger.info(f"Phase 4: Deleting old untagged upload entity {entity_id} from YTM")
        try:
            await ytm_client.delete_upload(entity_id)
        except Exception as e:
            logger.warning(f"Failed to delete old upload {entity_id} from YTM (non-fatal): {e}")

        # Mark deleted in memory so stale YTM continuation caches cannot resurrect it
        ytm_client.mark_deleted(entity_id)

        clean_title = req.title.strip()
        clean_artist = req.artist.strip() if req.artist else None
        clean_album = req.album.strip() if req.album else None
        clean_thumb = req.cover_url.strip() if req.cover_url else upload.thumbnail
        if clean_thumb and clean_thumb.startswith("data:image/"):
            try:
                import base64
                art_dir = settings.data_dir / "artwork"
                art_dir.mkdir(parents=True, exist_ok=True)
                _, b64_data = clean_thumb.split(",", 1)
                art_bytes = base64.b64decode(b64_data)
                art_file = art_dir / f"custom_{upload.video_id}.jpg"
                art_file.write_bytes(art_bytes)
                clean_thumb = f"/api/artwork/{art_file.name}"
            except Exception as e:
                logger.warning(f"Could not persist custom artwork: {e}")

        # Check if the retagged upload is still missing required metadata (artist, album, artwork, clean title)
        still_missing = (
            not clean_artist or clean_artist.lower() in ('unknown artist', 'unknown') or
            not clean_album or clean_album.lower() in ('unknown album', 'unknown') or
            not clean_thumb or
            clean_title.lower().endswith(('.mp3', '.flac', '.m4a', '.wav', '.opus', '.webm'))
        )

        # 5. If still missing any metadata, update local DB so it stays on list with fresh data.
        # If fully fixed, delete old untagged record so it disappears from missing metadata list.
        if still_missing:
            await db.update_ytm_upload(
                entity_id=entity_id,
                title=clean_title,
                artist=clean_artist,
                album=clean_album,
                thumbnail=clean_thumb
            )
        else:
            await db.delete_ytm_upload_record(entity_id)

        # Trigger delayed background refresh so YTM has time to process the newly uploaded file
        async def _delayed_refresh():
            await asyncio.sleep(20)
            try:
                await ytm_client.fetch_and_cache_uploads()
            except Exception as ex:
                logger.debug(f"Delayed YTM uploads refresh notice: {ex}")

        asyncio.create_task(_delayed_refresh())

        metadata_tracker.log_change(
            title=clean_title,
            artist=clean_artist,
            album=clean_album,
            thumbnail=clean_thumb,
            source="Cloud Upload Re-tagger",
            detail="Replaced and retagged on YouTube Music"
        )

        return {
            "status": "success",
            "message": f"Successfully retagged and replaced '{clean_title}' on YouTube Music.",
            "still_missing": still_missing,
            "title": clean_title,
            "artist": clean_artist,
            "album": clean_album,
            "thumbnail": clean_thumb
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Failed to replace upload {entity_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to replace upload: {str(e)}")
    finally:
        # Aggressive cleanup of temporary/staging audio files
        if downloaded_path and downloaded_path.exists():
            try:
                downloaded_path.unlink()
            except Exception:
                pass
        if upload and upload.video_id:
            staging_dir = settings.data_dir / "staging"
            if staging_dir.exists():
                for tmp_f in staging_dir.glob(f"*{upload.video_id}*"):
                    try:
                        tmp_f.unlink()
                    except Exception:
                        pass


@router.delete("/api/ytm/uploads/{entity_id}")
async def delete_ytm_upload(entity_id: str):
    """Delete an upload directly from YouTube Music and from the local database."""
    try:
        await ytm_client.delete_upload(entity_id)
        await db.delete_ytm_upload_record(entity_id)
        ytm_client.mark_deleted(entity_id)
        return {"status": "success", "message": f"Deleted upload entity {entity_id}."}
    except Exception as e:
        logger.error(f"Failed to delete upload {entity_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to delete upload: {str(e)}")


class BatchDeleteUploadsRequest(BaseModel):
    entity_ids: list[str] = Field(..., min_length=1, max_length=100, description="List of YTM upload entity IDs to delete (max 100)")

@router.post("/api/ytm/uploads/batch-delete")
async def batch_delete_ytm_uploads(req: BatchDeleteUploadsRequest):
    """Batch delete uploads directly from YouTube Music and from the local database."""
    deleted = 0
    failed = 0
    for eid in req.entity_ids:
        try:
            await ytm_client.delete_upload(eid)
            await db.delete_ytm_upload_record(eid)
            ytm_client.mark_deleted(eid)
            deleted += 1
        except Exception as e:
            logger.warning(f"Failed to delete upload {eid}: {e}")
            failed += 1
    return {"status": "success", "deleted": deleted, "failed": failed}


