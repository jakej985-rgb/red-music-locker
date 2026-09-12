"""Router module for Replicated Playlists endpoints."""
import logging

import asyncio

from fastapi import APIRouter, Depends, HTTPException

from ..models import (
    ReplicatedPlaylist,
    ReplicatedPlaylistCreate,
    ReplicatedPlaylistUpdate,
    User,
    UserRole
)
from ..database import db
from ..dependencies import require_authenticated_user
from ..rate_limiter import rate_limit_dependency
from ..ytm_client import ytm_client
from ..playlist_downloader import playlist_sync_manager
from ..playlist_replicator import playlist_replicator

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Replicated Playlists"])

@router.get("/api/replicated-playlists")
async def list_replicated_playlists(current_user: User = Depends(require_authenticated_user)):
    """List all configured replicated playlist watchers with current status."""
    try:
        replicas = await db.get_replicated_playlists(user_id=current_user.id)
        results = []
        for r in replicas:
            results.append(r.model_dump())
        return results
    except Exception as e:
        logger.exception(f"Failed to list replicated playlists: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list replicated playlists: {e}")


@router.post("/api/replicated-playlists", dependencies=[Depends(rate_limit_dependency(20, 60, "playlist_create", use_user_id=True))])
async def create_replicated_playlist(req: ReplicatedPlaylistCreate, current_user: User = Depends(require_authenticated_user)):
    """Configure a new replicated playlist watcher (supports multi-account target selection)."""
    try:
        # If source name not supplied, fetch it from YouTube Music
        source_name = req.source_playlist_name
        if not source_name:
            try:
                details = await ytm_client.get_playlist_details(req.source_playlist_id, user_id=current_user.id)
                source_name = details.get("title", f"Playlist {req.source_playlist_id}")
            except Exception:
                source_name = f"Playlist {req.source_playlist_id}"

        dest_name = req.destination_playlist_name or f"{source_name} - Locker"
        dest_id = req.destination_playlist_id or ""

        # Determine target user IDs (ignore spoofed/payload user_id; multi-target replication uses target_user_ids)
        raw_target_uids = req.target_user_ids if req.target_user_ids else [current_user.id]
        created_replicas = []

        permitted_accounts = await db.get_permitted_family_accounts(current_user.id)
        permitted_lookup = {a.get("user_id"): a for a in permitted_accounts}

        for uid in raw_target_uids:
            # Validate permissions if target is another user
            if uid != current_user.id:
                account_info = permitted_lookup.get(uid)
                if not account_info or not account_info.get("allow_family_playlists"):
                    logger.warning(f"User {uid} does not permit family playlists from {current_user.id}")
                    continue

            existing = await db.get_replicated_playlist_by_source_id(req.source_playlist_id, user_id=uid)
            if existing:
                created_replicas.append(existing)
                continue

            new_id = await db.create_replicated_playlist(
                source_playlist_id=req.source_playlist_id,
                source_playlist_name=source_name,
                destination_playlist_id=dest_id,
                destination_playlist_name=dest_name,
                enabled=req.enabled,
                sync_interval_seconds=req.sync_interval_seconds,
                user_id=uid
            )
            created = await db.get_replicated_playlist(new_id, user_id=uid)
            if created:
                created_replicas.append(created)

        # Trigger immediate reconciliation for target accounts
        for rep in created_replicas:
            try:
                asyncio.create_task(playlist_replicator.reconcile_playlist(rep.id, dry_run=False))
            except Exception as ex:
                logger.warning(f"Could not trigger background reconciliation for replica {rep.id}: {ex}")

        # If user also requested uploading missing tracks to targets
        if req.upload_missing_to_targets and created_replicas:
            try:
                details = await ytm_client.get_playlist_details(req.source_playlist_id, user_id=current_user.id)
                tracks = details.get("tracks", [])
                valid_uids = [r.user_id for r in created_replicas if r.user_id]
                playlist_sync_manager.start_sync(
                    playlist_id=req.source_playlist_id,
                    playlist_title=source_name,
                    tracks_to_sync=tracks,
                    destination_user_ids=valid_uids
                )
            except Exception as ex:
                logger.warning(f"Could not launch multi-account track upload sync: {ex}")

        if not created_replicas:
            raise HTTPException(status_code=400, detail="No replicated playlists could be created for the selected accounts")

        # Return primary replica for current user if present, else first created
        primary = next((r for r in created_replicas if r.user_id == current_user.id), created_replicas[0])
        res = primary.model_dump()
        res["created_replicas_count"] = len(created_replicas)
        res["target_user_ids"] = [r.user_id for r in created_replicas]
        return res
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Failed to create replicated playlist: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create replicated playlist: {e}")


async def _validate_playlist_access(config, current_user: User) -> bool:
    if not config:
        return False
    if current_user.role == UserRole.ADMIN or config.user_id == current_user.id:
        return True
    permitted = await db.get_permitted_family_accounts(current_user.id)
    return any(a.get("user_id") == config.user_id and a.get("allow_family_playlists") for a in permitted)


@router.get("/api/replicated-playlists/{replicated_id}")
async def get_replicated_playlist(replicated_id: int, current_user: User = Depends(require_authenticated_user)):
    """Get details, current configuration, and status of a replicated playlist."""
    config = await db.get_replicated_playlist(replicated_id)
    if not await _validate_playlist_access(config, current_user):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")

    # Run preview/dry-run to return stats (source count, locker matches, excluded count)
    try:
        preview = await playlist_replicator.reconcile_playlist(replicated_id, dry_run=True, config=config)
    except Exception as e:
        logger.warning(f"Could not calculate preview for replica {replicated_id}: {e}")
        preview = None

    res = dict(preview) if preview else {}
    res["config"] = config.model_dump()
    res["preview"] = preview
    return res


@router.put("/api/replicated-playlists/{replicated_id}")
async def update_replicated_playlist(replicated_id: int, req: ReplicatedPlaylistUpdate, current_user: User = Depends(require_authenticated_user)):
    """Update settings for an existing replicated playlist watcher."""
    config = await db.get_replicated_playlist(replicated_id)
    if not config or (current_user.role != UserRole.ADMIN and config.user_id != current_user.id):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")

    update_dict = {k: v for k, v in req.model_dump().items() if v is not None}
    target_user_id = None if current_user.role == UserRole.ADMIN else current_user.id
    updated = await db.update_replicated_playlist(replicated_id, user_id=target_user_id, **update_dict)
    return updated.model_dump() if updated else {}


@router.delete("/api/replicated-playlists/{replicated_id}")
async def delete_replicated_playlist(replicated_id: int, current_user: User = Depends(require_authenticated_user)):
    """Delete a replicated playlist watcher configuration."""
    target_user_id = None if current_user.role == UserRole.ADMIN else current_user.id
    deleted = await db.delete_replicated_playlist(replicated_id, user_id=target_user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Replicated playlist not found")
    return {"status": "ok", "message": f"Deleted replica watcher {replicated_id}"}


@router.post("/api/replicated-playlists/{replicated_id}/sync", dependencies=[Depends(rate_limit_dependency(10, 60, "playlist_sync", use_user_id=True))])
async def sync_replicated_playlist(replicated_id: int, current_user: User = Depends(require_authenticated_user)):
    """Trigger immediate reconciliation of a replicated playlist."""
    config = await db.get_replicated_playlist(replicated_id)
    if not await _validate_playlist_access(config, current_user):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")
    try:
        res = await playlist_replicator.reconcile_playlist(replicated_id, dry_run=False, config=config)
        return res
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        logger.exception(f"Reconciliation failed for replica {replicated_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Reconciliation failed: {e}")


@router.post("/api/replicated-playlists/{replicated_id}/dry-run")
async def dry_run_replicated_playlist(replicated_id: int, current_user: User = Depends(require_authenticated_user)):
    """Preview reconciliation actions (add, remove, move, exclude) without modifying YouTube Music."""
    config = await db.get_replicated_playlist(replicated_id)
    if not await _validate_playlist_access(config, current_user):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")
    try:
        res = await playlist_replicator.reconcile_playlist(replicated_id, dry_run=True, config=config)
        return res
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        logger.exception(f"Dry-run failed for replica {replicated_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Dry-run failed: {e}")


@router.get("/api/replicated-playlists/{replicated_id}/events")
async def get_replicated_playlist_events(replicated_id: int, limit: int = 100, current_user: User = Depends(require_authenticated_user)):
    """Get audit trail of reconciliation actions (ADD, REMOVE, MOVE, NOOP, EXCLUDE)."""
    config = await db.get_replicated_playlist(replicated_id)
    if not await _validate_playlist_access(config, current_user):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")
    events = await db.get_replicated_playlist_events(replicated_id, limit=limit)
    return events


@router.get("/api/replicated-playlists/{replicated_id}/snapshots/latest")
async def get_latest_playlist_snapshot(replicated_id: int, current_user: User = Depends(require_authenticated_user)):
    """Get the most recent SourcePlaylistSnapshot for a replica (Section 4 of plan)."""
    config = await db.get_replicated_playlist(replicated_id)
    if not config or (current_user.role != UserRole.ADMIN and config.user_id != current_user.id):
        raise HTTPException(status_code=404, detail="Replicated playlist not found")
    snapshot = await db.get_latest_replicated_playlist_snapshot(replicated_id)
    if not snapshot:
        raise HTTPException(status_code=404, detail="No snapshot found for this replicated playlist")
    return snapshot


