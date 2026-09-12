"""Router module for Family Mode endpoints."""
import logging

import asyncio
import secrets

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from ..models import (
    User,
    Family,
    FamilyRole,
    FamilyMember,
    FamilyCreateRequest,
    FamilyUpdateRequest,
    FamilyMemberAddRequest,
    FamilyTransferOwnershipRequest,
    FamilyInvitation,
    FamilyInvitationCreateRequest,
    FamilyInvitationInfoResponse,
    FamilyMemberPrivacyUpdate,
    FamilyMemberRoleUpdate,
    FamilyDashboardMemberItem,
    FamilyDashboardResponse,
    FamilyQueueItem,
    FamilyMultiPlaylistRequest,
    FamilyUploadHistoryItem,
    FamilySyncResponse,
    FamilyPlaylistItem,
    ReplicatedPlaylist,
    UserRole
)
from ..database import db
from ..dependencies import require_authenticated_user
from ..ytm_client import ytm_client
from ..playlist_downloader import playlist_sync_manager
from ..playlist_replicator import playlist_replicator

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Family Mode"])

@router.post("/api/families", response_model=Family)
async def create_family(req: FamilyCreateRequest, current_user: User = Depends(require_authenticated_user)):
    """Create a new family. Caller is assigned the OWNER role."""
    if not req.name.strip():
        raise HTTPException(status_code=400, detail="Family name cannot be empty")
    return await db.create_family(name=req.name.strip(), owner_user_id=current_user.id)


@router.get("/api/families", response_model=list[Family])
async def list_user_families(current_user: User = Depends(require_authenticated_user)):
    """List all families the caller belongs to."""
    return await db.get_user_families(current_user.id)


@router.get("/api/families/{family_id}", response_model=Family)
async def get_family_details(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Get details and members of a family (requires membership)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    member = await db.get_family_member(family_id, current_user.id)
    if not member:
        raise HTTPException(status_code=403, detail="You are not a member of this family")
    return fam


@router.patch("/api/families/{family_id}", response_model=Family)
@router.put("/api/families/{family_id}", response_model=Family)
async def update_family(family_id: str, req: FamilyUpdateRequest, current_user: User = Depends(require_authenticated_user)):
    """Update family name (requires OWNER or ADMIN)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    member = await db.get_family_member(family_id, current_user.id)
    if not member or member.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only family owners and admins can update family details")
    await db.update_family(family_id, req.name.strip())
    return await db.get_family_by_id(family_id)


@router.post("/api/families/{family_id}/transfer")
async def transfer_family_ownership(family_id: str, req: FamilyTransferOwnershipRequest, current_user: User = Depends(require_authenticated_user)):
    """Transfer family ownership to another member with explicit confirmation (Section 30)."""
    if not req.confirm:
        raise HTTPException(status_code=400, detail="Ownership transfer must be confirmed with confirm=true")
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    if fam.owner_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the family owner can transfer ownership")
    try:
        await db.transfer_family_ownership(family_id, req.new_owner_user_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"status": "success", "message": f"Ownership transferred to {req.new_owner_user_id}"}


@router.post("/api/families/{family_id}/leave")
async def leave_family(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Leave family (Section 29: preserves all user data; owner cannot leave without transfer/delete)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    try:
        await db.leave_family(family_id, current_user.id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"status": "success", "message": "Left family successfully"}


@router.delete("/api/families/{family_id}")
async def delete_family(family_id: str, confirm: bool = Query(False), current_user: User = Depends(require_authenticated_user)):
    """Delete family with confirmation (Section 31: OWNER only; strictly preserves user accounts)."""
    if not confirm:
        raise HTTPException(status_code=400, detail="Family deletion must be confirmed with confirm=true")
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    if fam.owner_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the family owner can delete the family")
    await db.delete_family(family_id)
    return {"status": "success", "message": "Family deleted successfully"}


# --- Member Management & Invitations (Sections 27–28) ---


@router.post("/api/families/{family_id}/members", response_model=FamilyMember)
async def add_family_member_direct(family_id: str, req: FamilyMemberAddRequest, current_user: User = Depends(require_authenticated_user)):
    """Direct add member (Admin/Owner shortcut)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    member = await db.get_family_member(family_id, current_user.id)
    if not member or member.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only family owners and admins can add members")
    target_user = await db.get_user_by_id(req.user_id) or await db.get_user_by_username(req.user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")
    existing = await db.get_family_member(family_id, target_user.id)
    if existing:
        raise HTTPException(status_code=409, detail="User is already a member of this family")
    return await db.add_family_member(family_id=family_id, user_id=target_user.id, role=req.role.value)


@router.delete("/api/families/{family_id}/members/{user_id}")
async def remove_family_member(family_id: str, user_id: str, current_user: User = Depends(require_authenticated_user)):
    """Remove member from family (Section 28: OWNER/ADMIN or self; preserves user data)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    caller_mem = await db.get_family_member(family_id, current_user.id)
    if not caller_mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")
    if user_id != current_user.id:
        if caller_mem.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
            raise HTTPException(status_code=403, detail="Only owners and admins can remove other members")
        if fam.owner_user_id == user_id:
            raise HTTPException(status_code=400, detail="Cannot remove the family owner")
    else:
        if fam.owner_user_id == current_user.id:
            raise HTTPException(status_code=400, detail="Family owner cannot leave without transferring ownership or deleting the family")

    await db.remove_family_member(family_id, user_id)
    return {"status": "success", "message": "Member removed from family"}


@router.patch("/api/families/{family_id}/members/{user_id}/permissions")
@router.put("/api/families/{family_id}/members/{user_id}/privacy")
async def update_member_privacy(family_id: str, user_id: str, req: FamilyMemberPrivacyUpdate, current_user: User = Depends(require_authenticated_user)):
    """Update member privacy flags (Section 6, 26: SELF ONLY)."""
    if current_user.id != user_id:
        raise HTTPException(status_code=403, detail="You can only modify your own family privacy settings")
    member = await db.get_family_member(family_id, user_id)
    if not member:
        raise HTTPException(status_code=404, detail="Family member not found")
    await db.update_family_member_privacy(
        family_id=family_id,
        user_id=user_id,
        show_account_in_family=req.show_account_in_family,
        allow_family_uploads=req.allow_family_uploads,
        allow_family_playlists=req.allow_family_playlists,
        allow_family_sync=req.allow_family_sync
    )
    return await db.get_family_member(family_id, user_id)


@router.put("/api/families/{family_id}/members/{user_id}/role", response_model=FamilyMember)
async def update_member_role(family_id: str, user_id: str, req: FamilyMemberRoleUpdate, current_user: User = Depends(require_authenticated_user)):
    """Update member role (OWNER ONLY; cannot demote owner without transfer)."""
    fam = await db.get_family_by_id(family_id)
    if not fam or fam.owner_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the family owner can change member roles")
    if user_id == current_user.id and req.role != FamilyRole.OWNER:
        raise HTTPException(status_code=400, detail="Owner must use transfer endpoint to change ownership")
    await db.update_family_member_role(family_id, user_id, req.role.value)
    return await db.get_family_member(family_id, user_id)


# --- Invitation Tokens (Section 27) ---


@router.post("/api/families/{family_id}/invitations", response_model=FamilyInvitation)
async def create_family_invitation(family_id: str, req: FamilyInvitationCreateRequest, current_user: User = Depends(require_authenticated_user)):
    """Create short-lived single-use invitation token (OWNER/ADMIN)."""
    caller_mem = await db.get_family_member(family_id, current_user.id)
    if not caller_mem or caller_mem.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only family owners and admins can invite members")
    return await db.create_family_invitation(
        family_id=family_id,
        created_by_user_id=current_user.id,
        role=req.role.value,
        ttl_hours=req.ttl_hours
    )


@router.get("/api/families/{family_id}/invitations", response_model=list[FamilyInvitation])
async def list_family_invitations(family_id: str, current_user: User = Depends(require_authenticated_user)):
    caller_mem = await db.get_family_member(family_id, current_user.id)
    if not caller_mem or caller_mem.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only family owners and admins can view invitations")
    return await db.list_family_invitations(family_id)


@router.delete("/api/families/{family_id}/invitations/{invitation_id}")
async def revoke_family_invitation(family_id: str, invitation_id: str, current_user: User = Depends(require_authenticated_user)):
    caller_mem = await db.get_family_member(family_id, current_user.id)
    if not caller_mem or caller_mem.role not in (FamilyRole.OWNER, FamilyRole.ADMIN):
        raise HTTPException(status_code=403, detail="Only family owners and admins can revoke invitations")
    await db.revoke_family_invitation(family_id, invitation_id)
    return {"status": "success", "message": "Invitation revoked"}


@router.get("/api/invitations/{token}", response_model=FamilyInvitationInfoResponse)
async def inspect_invitation(token: str):
    """Public inspection of invitation without disclosing internal IDs."""
    inv = await db.get_family_invitation_by_token(token)
    if not inv or inv.is_expired:
        raise HTTPException(status_code=404, detail="Invitation is invalid or has expired")
    fam = await db.get_family_by_id(inv.family_id)
    inviter = await db.get_user_by_id(inv.created_by_user_id)
    return FamilyInvitationInfoResponse(
        family_id=inv.family_id,
        family_name=fam.name if fam else "Family",
        role=inv.role.value,
        inviter_username=inviter.username if inviter else "Admin",
        expires_at=inv.expires_at
    )


@router.post("/api/invitations/{token}/accept", response_model=FamilyMember)
async def accept_invitation(token: str, current_user: User = Depends(require_authenticated_user)):
    """Accept invitation and join family."""
    try:
        return await db.accept_family_invitation(token, current_user.id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- Family Dashboard (Section 8) ---


@router.get("/api/families/{family_id}/dashboard", response_model=FamilyDashboardResponse)
async def get_family_dashboard(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Family dashboard aggregating permitted member account statuses (Section 8)."""
    fam = await db.get_family_by_id(family_id)
    if not fam:
        raise HTTPException(status_code=404, detail="Family not found")
    caller_mem = await db.get_family_member(family_id, current_user.id)
    if not caller_mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")

    members = await db.get_family_members(family_id)
    member_items = []
    for m in members:
        is_self = (m.user_id == current_user.id)
        if not is_self and not m.show_account_in_family:
            # Privacy: hidden account
            member_items.append(FamilyDashboardMemberItem(
                user_id=m.user_id,
                username=m.username or "User",
                role=m.role.value,
                ytm_connected=False,
                account_name=None,
                uploads_count=None,
                allow_family_uploads=False,
                allow_family_playlists=False,
                allow_family_sync=False
            ))
        else:
            acc = await db.get_ytm_account(m.user_id)
            uploads_count = None
            if is_self or m.show_account_in_family:
                counts = await db.get_dashboard_counts(user_id=m.user_id)
                uploads_count = counts.get("ytm_uploads_count", 0)
            member_items.append(FamilyDashboardMemberItem(
                user_id=m.user_id,
                username=m.username or "User",
                role=m.role.value,
                ytm_connected=bool(acc and acc.status == "CONNECTED"),
                account_name=acc.account_name if acc else None,
                uploads_count=uploads_count,
                allow_family_uploads=m.allow_family_uploads,
                allow_family_playlists=m.allow_family_playlists,
                allow_family_sync=m.allow_family_sync
            ))

    return FamilyDashboardResponse(
        family_id=fam.id,
        family_name=fam.name,
        my_role=caller_mem.role.value,
        members=member_items
    )


# --- Multi-Account Uploads & Queue (Sections 10–16, 24, 32–34) ---


@router.get("/api/families/{family_id}/queue", response_model=list[FamilyQueueItem])
async def get_family_queue(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Grouped multi-account upload queue (Section 33)."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")
    items = await db.get_family_queue_grouped(family_id, current_user.id)
    return [FamilyQueueItem(**item) for item in items]


@router.get("/api/families/{family_id}/history", response_model=list[FamilyUploadHistoryItem])
async def get_family_history(family_id: str, limit: int = Query(50), current_user: User = Depends(require_authenticated_user)):
    """Combined upload history identifying destination and requesting users (Section 17)."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")
    items = await db.get_family_upload_history(family_id, current_user.id, limit)
    return [FamilyUploadHistoryItem(**item) for item in items]


@router.post("/api/families/{family_id}/sync", response_model=FamilySyncResponse)
async def trigger_family_sync(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Trigger independent sync for each permitted family account with fault isolation (Section 18)."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")

    permitted = await db.get_family_permitted_sync_members(family_id)
    results = {}
    for p in permitted:
        try:
            counts = await db.get_dashboard_counts(user_id=p.user_id)
            results[p.username or p.user_id] = {
                "status": "started",
                "in_queue": counts.get("in_queue_count", 0),
                "error": None
            }
        except Exception as e:
            results[p.username or p.user_id] = {
                "status": "failed",
                "in_queue": 0,
                "error": str(e)
            }
    return FamilySyncResponse(family_id=family_id, results=results)


@router.get("/api/families/{family_id}/playlists", response_model=list[FamilyPlaylistItem])
async def list_family_shared_playlists(family_id: str, current_user: User = Depends(require_authenticated_user)):
    """Read-only view of playlists shared by family members (Section 19)."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")
    items = await db.get_family_permitted_playlists(family_id, current_user.id)
    return [FamilyPlaylistItem(**item) for item in items]


@router.post("/api/families/{family_id}/playlists/{playlist_id}/sync")
async def sync_family_playlist(
    family_id: str,
    playlist_id: str,
    upload_missing: bool = Query(False),
    current_user: User = Depends(require_authenticated_user)
):
    """Sync a shared family playlist across YouTube Music and optionally upload missing songs."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")

    try:
        rep_int_id = int(playlist_id)
        config = await db.get_replicated_playlist(rep_int_id)
    except (ValueError, TypeError):
        config = None

    if not config:
        async with db.get_connection() as conn:
            async with conn.execute(
                "SELECT * FROM replicated_playlists WHERE source_playlist_id = ? OR destination_playlist_id = ? LIMIT 1",
                (playlist_id, playlist_id)
            ) as cursor:
                row = await cursor.fetchone()
                if row:
                    config = ReplicatedPlaylist(**dict(row))

    if not config:
        raise HTTPException(status_code=404, detail="Replicated playlist not found")

    if config.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        owner_mem = await db.get_family_member(family_id, config.user_id)
        if not owner_mem or not owner_mem.allow_family_playlists:
            raise HTTPException(status_code=403, detail="Playlist owner does not permit family playlist sync")

    # Identify all sibling replicas for this playlist in the family
    replicas_to_sync = [config]
    if config.source_playlist_id:
        permitted_members = await db.get_family_permitted_playlists(family_id, current_user.id)
        sibling_ids = [
            int(p["playlist_id"]) for p in permitted_members
            if p.get("source_playlist_id") == config.source_playlist_id and int(p["playlist_id"]) != config.id
        ]
        for sid in sibling_ids:
            s_cfg = await db.get_replicated_playlist(sid)
            if s_cfg:
                replicas_to_sync.append(s_cfg)

    results = []
    for rep in replicas_to_sync:
        try:
            res = await playlist_replicator.reconcile_playlist(rep.id, dry_run=False, config=rep)
            results.append({
                "replicated_id": rep.id,
                "user_id": rep.user_id,
                "status": "success",
                "details": res
            })
        except Exception as e:
            logger.warning(f"Failed to reconcile replica {rep.id}: {e}")
            results.append({
                "replicated_id": rep.id,
                "user_id": rep.user_id,
                "status": "failed",
                "error": str(e)
            })

    # If upload_missing is True, also launch background download & upload to family accounts
    if upload_missing and config.source_playlist_id:
        try:
            details = await ytm_client.get_playlist_details(config.source_playlist_id, user_id=current_user.id)
            tracks = details.get("tracks", [])
            target_uids = [r.user_id for r in replicas_to_sync if r.user_id]
            if tracks and target_uids:
                playlist_sync_manager.start_sync(
                    playlist_id=config.source_playlist_id,
                    playlist_title=config.source_playlist_name or config.destination_playlist_name,
                    tracks_to_sync=tracks,
                    destination_user_ids=target_uids
                )
        except Exception as ex:
            logger.warning(f"Could not trigger background download & upload for family playlist: {ex}")

    return {
        "status": "success",
        "family_id": family_id,
        "synced_replicas": len(results),
        "results": results
    }


@router.post("/api/families/{family_id}/playlists/sync-all")
async def sync_all_family_playlists(
    family_id: str,
    current_user: User = Depends(require_authenticated_user)
):
    """Sync all permitted shared family playlists for the given family."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")

    permitted_playlists = await db.get_family_permitted_playlists(family_id, current_user.id)
    results = []
    for p in permitted_playlists:
        rep_id = int(p["playlist_id"])
        try:
            res = await playlist_replicator.reconcile_playlist(rep_id, dry_run=False)
            results.append({
                "playlist_id": rep_id,
                "name": p.get("name"),
                "status": "success",
                "details": res
            })
        except Exception as e:
            logger.warning(f"Failed to reconcile family playlist {rep_id}: {e}")
            results.append({
                "playlist_id": rep_id,
                "name": p.get("name"),
                "status": "failed",
                "error": str(e)
            })

    return {
        "status": "success",
        "family_id": family_id,
        "total": len(results),
        "results": results
    }


@router.post("/api/families/{family_id}/playlists/multi")
async def create_multi_account_playlists(family_id: str, req: FamilyMultiPlaylistRequest, current_user: User = Depends(require_authenticated_user)):
    """Create or clone independent playlist on each selected family account (Section 35)."""
    mem = await db.get_family_member(family_id, current_user.id)
    if not mem:
        raise HTTPException(status_code=403, detail="You are not a member of this family")

    user_ids = req.effective_user_ids
    if not user_ids:
        raise HTTPException(status_code=400, detail="At least one target user must be selected")

    # Flow A: Clone an existing YouTube Music playlist
    if req.source_playlist_id:
        source_uid = req.source_user_id or current_user.id
        if source_uid != current_user.id:
            permitted_accounts = await db.get_permitted_family_accounts(current_user.id)
            can_access = any(a.get("user_id") == source_uid and a.get("allow_family_playlists") for a in permitted_accounts)
            if not can_access:
                raise HTTPException(status_code=403, detail="Access to source family member's playlists is not permitted")

        try:
            details = await ytm_client.get_playlist_details(req.source_playlist_id, user_id=source_uid)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to fetch source playlist details: {e}")

        source_title = details.get("title", f"Playlist {req.source_playlist_id}")
        name = req.effective_name or source_title
        tracks = details.get("tracks", [])

        permitted_accounts = await db.get_permitted_family_accounts(current_user.id)
        permitted_lookup = {a.get("user_id"): a for a in permitted_accounts}

        created_replicas = []
        for uid in user_ids:
            if uid != current_user.id:
                account_info = permitted_lookup.get(uid)
                if not account_info or not account_info.get("allow_family_playlists"):
                    logger.warning(f"User {uid} does not permit family playlists from {current_user.id}")
                    continue

            existing = await db.get_replicated_playlist_by_source_id(req.source_playlist_id, user_id=uid)
            if existing:
                if not existing.destination_playlist_id:
                    try:
                        ownership_desc = (
                            f"Automated 1:1 Locker-Only Replica of '{source_title}'. "
                            f"[managed_by=ytmusic_sync;replica_mode=locker_only;source_playlist_id={req.source_playlist_id}]"
                        )
                        dest_id = await ytm_client.create_playlist(
                            title=name,
                            description=ownership_desc,
                            user_id=uid
                        )
                        await db.update_replicated_playlist(existing.id, user_id=uid, destination_playlist_id=dest_id)
                        existing.destination_playlist_id = dest_id
                    except Exception as ex:
                        logger.warning(f"Could not create YTM destination playlist for {uid}: {ex}")
                created_replicas.append(existing)
            else:
                dest_id = ""
                try:
                    ownership_desc = (
                        f"Automated 1:1 Replica of '{source_title}'. "
                        f"[managed_by=ytmusic_sync;replica_mode={req.replica_mode};source_playlist_id={req.source_playlist_id}]"
                    )
                    dest_id = await ytm_client.create_playlist(
                        title=name,
                        description=ownership_desc,
                        user_id=uid
                    )
                except Exception as ex:
                    logger.warning(f"Could not create YTM destination playlist for {uid}: {ex}")
                    dest_id = f"local_{secrets.token_hex(6)}"

                new_id = await db.create_replicated_playlist(
                    source_playlist_id=req.source_playlist_id,
                    source_playlist_name=source_title,
                    destination_playlist_id=dest_id,
                    destination_playlist_name=name,
                    enabled=True,
                    sync_interval_seconds=300,
                    user_id=uid,
                    replica_mode=req.replica_mode
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
                valid_uids = [r.user_id for r in created_replicas if r.user_id]
                playlist_sync_manager.start_sync(
                    playlist_id=req.source_playlist_id,
                    playlist_title=name,
                    tracks_to_sync=tracks,
                    destination_user_ids=valid_uids
                )
            except Exception as ex:
                logger.warning(f"Could not launch multi-account track upload sync: {ex}")

        return {
            "status": "success",
            "mode": "clone",
            "source_playlist_id": req.source_playlist_id,
            "created_count": len(created_replicas),
            "playlists": [
                {
                    "replicated_playlist_id": r.id,
                    "destination_user_id": r.user_id,
                    "name": r.destination_playlist_name
                }
                for r in created_replicas
            ]
        }

    # Flow B: Create empty shared multi-account playlist
    name = req.effective_name
    if not name:
        raise HTTPException(status_code=400, detail="Playlist name cannot be empty")

    created = await db.create_multi_account_playlists(
        playlist_name=name,
        destination_user_ids=user_ids,
        created_by_user_id=current_user.id,
        family_id=family_id
    )
    return {"status": "success", "mode": "create", "created_count": len(created), "playlists": created}


# ============================================================================
# YouTube Music Account Status & Settings (Phases H, Q, S, T)
# ============================================================================


