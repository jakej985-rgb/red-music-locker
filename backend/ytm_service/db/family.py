"""Database mixin for family sharing, membership, invitations, and permissions."""
import aiosqlite
import json
import logging
import secrets
import sqlite3
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..models import (
    Family, FamilyMember, FamilyInvitation,
    FamilyRole, FamilyMemberStatus, SyncJob, ReplicatedPlaylist
)
from .base import logger


class FamilyDbMixin:
    """Family creation, membership roles, sharing permissions, and multi-account sync."""
    async def create_family(self, name: str, owner_user_id: str) -> Family:
        family_id = f"family_{secrets.token_hex(8)}"
        member_id = f"fmem_{secrets.token_hex(8)}"
        async with self.get_connection() as db:
            await db.execute(
                "INSERT INTO families (id, name, owner_user_id) VALUES (?, ?, ?)",
                (family_id, name, owner_user_id)
            )
            await db.execute(
                """
                INSERT INTO family_members (
                    id, family_id, user_id, role, status,
                    show_account_in_family, allow_family_uploads, allow_family_playlists, allow_family_sync
                ) VALUES (?, ?, ?, 'OWNER', 'ACTIVE', 1, 1, 0, 0)
                """,
                (member_id, family_id, owner_user_id)
            )
            await db.commit()
        fam = await self.get_family_by_id(family_id)
        if not fam:
            raise ValueError("Failed to create family")
        return fam

    async def get_family_by_id(self, family_id: str) -> Optional[Family]:
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT f.*, u.username as owner_username
                FROM families f
                LEFT JOIN users u ON f.owner_user_id = u.id
                WHERE f.id = ?
                """,
                (family_id,)
            ) as cursor:
                f_row = await cursor.fetchone()
                if not f_row:
                    return None
                f_dict = dict(f_row)

        members = await self.get_family_members(family_id)
        return Family(
            id=f_dict["id"],
            name=f_dict["name"],
            owner_user_id=f_dict["owner_user_id"],
            owner_username=f_dict.get("owner_username"),
            created_at=f_dict.get("created_at"),
            updated_at=f_dict.get("updated_at"),
            members=members
        )

    async def get_user_families(self, user_id: str) -> list[Family]:
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT DISTINCT f.id
                FROM families f
                JOIN family_members fm ON f.id = fm.family_id
                WHERE fm.user_id = ? AND fm.status = 'ACTIVE'
                ORDER BY f.created_at ASC
                """,
                (user_id,)
            ) as cursor:
                rows = await cursor.fetchall()
                family_ids = [row["id"] for row in rows]

        families = []
        for fid in family_ids:
            fam = await self.get_family_by_id(fid)
            if fam:
                families.append(fam)
        return families

    async def update_family(self, family_id: str, name: str) -> bool:
        async with self.get_connection() as db:
            cursor = await db.execute(
                "UPDATE families SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (name, family_id)
            )
            await db.commit()
            return cursor.rowcount > 0

    async def transfer_family_ownership(self, family_id: str, new_owner_user_id: str) -> bool:
        """Transfer family ownership to another active member (Section 30)."""
        async with self.get_connection() as db:
            # Validate target is an active member
            async with db.execute(
                "SELECT role FROM family_members WHERE family_id = ? AND user_id = ? AND status = 'ACTIVE'",
                (family_id, new_owner_user_id)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    raise ValueError("Target user is not an active member of this family")

            # Update family owner
            await db.execute(
                "UPDATE families SET owner_user_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (new_owner_user_id, family_id)
            )
            # Demote old owner to ADMIN
            await db.execute(
                "UPDATE family_members SET role = 'ADMIN', updated_at = CURRENT_TIMESTAMP WHERE family_id = ? AND role = 'OWNER'",
                (family_id,)
            )
            # Promote new owner to OWNER
            await db.execute(
                "UPDATE family_members SET role = 'OWNER', updated_at = CURRENT_TIMESTAMP WHERE family_id = ? AND user_id = ?",
                (family_id, new_owner_user_id)
            )
            await db.commit()
            return True

    async def delete_family(self, family_id: str) -> bool:
        """Delete family and relationships without deleting users or their YTM data (Section 31)."""
        async with self.get_connection() as db:
            await db.execute("DELETE FROM family_invitations WHERE family_id = ?", (family_id,))
            await db.execute("DELETE FROM family_members WHERE family_id = ?", (family_id,))
            cursor = await db.execute("DELETE FROM families WHERE id = ?", (family_id,))
            await db.commit()
            return cursor.rowcount > 0

    async def leave_family(self, family_id: str, user_id: str) -> bool:
        """Allow a member to leave family, strictly preserving personal data (Section 29)."""
        fam = await self.get_family_by_id(family_id)
        if not fam:
            raise ValueError("Family not found")
        if fam.owner_user_id == user_id:
            raise ValueError("Family owner cannot leave without transferring ownership or deleting the family.")

        return await self.remove_family_member(family_id, user_id)

    async def add_family_member(
        self,
        family_id: str,
        user_id: str,
        role: str = "MEMBER",
        show_account_in_family: bool = True,
        allow_family_uploads: bool = True,
        allow_family_playlists: bool = False,
        allow_family_sync: bool = False
    ) -> FamilyMember:
        member_id = f"fmem_{secrets.token_hex(8)}"
        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO family_members (
                    id, family_id, user_id, role, status,
                    show_account_in_family, allow_family_uploads, allow_family_playlists, allow_family_sync
                ) VALUES (?, ?, ?, ?, 'ACTIVE', ?, ?, ?, ?)
                """,
                (
                    member_id, family_id, user_id, role,
                    1 if show_account_in_family else 0,
                    1 if allow_family_uploads else 0,
                    1 if allow_family_playlists else 0,
                    1 if allow_family_sync else 0
                )
            )
            await db.commit()

        mem = await self.get_family_member(family_id, user_id)
        if not mem:
            raise ValueError("Failed to add family member")
        return mem

    async def get_family_member(self, family_id: str, user_id: str) -> Optional[FamilyMember]:
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT fm.*, u.username
                FROM family_members fm
                JOIN users u ON fm.user_id = u.id
                WHERE fm.family_id = ? AND fm.user_id = ?
                """,
                (family_id, user_id)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                return FamilyMember(
                    id=row["id"],
                    family_id=row["family_id"],
                    user_id=row["user_id"],
                    username=row["username"],
                    role=FamilyRole(row["role"]),
                    status=FamilyMemberStatus(row["status"]),
                    show_account_in_family=bool(row["show_account_in_family"]),
                    allow_family_uploads=bool(row["allow_family_uploads"]),
                    allow_family_playlists=bool(row["allow_family_playlists"]),
                    allow_family_sync=bool(row["allow_family_sync"]),
                    created_at=row["created_at"],
                    updated_at=row["updated_at"]
                )

    async def get_family_members(self, family_id: str) -> list[FamilyMember]:
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT fm.*, u.username
                FROM family_members fm
                JOIN users u ON fm.user_id = u.id
                WHERE fm.family_id = ?
                ORDER BY CASE WHEN fm.role = 'OWNER' THEN 0 WHEN fm.role = 'ADMIN' THEN 1 ELSE 2 END, fm.created_at ASC
                """,
                (family_id,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [
                    FamilyMember(
                        id=row["id"],
                        family_id=row["family_id"],
                        user_id=row["user_id"],
                        username=row["username"],
                        role=FamilyRole(row["role"]),
                        status=FamilyMemberStatus(row["status"]),
                        show_account_in_family=bool(row["show_account_in_family"]),
                        allow_family_uploads=bool(row["allow_family_uploads"]),
                        allow_family_playlists=bool(row["allow_family_playlists"]),
                        allow_family_sync=bool(row["allow_family_sync"]),
                        created_at=row["created_at"],
                        updated_at=row["updated_at"]
                    )
                    for row in rows
                ]

    async def update_family_member_privacy(
        self,
        family_id: str,
        user_id: str,
        show_account_in_family: Optional[bool] = None,
        allow_family_uploads: Optional[bool] = None,
        allow_family_playlists: Optional[bool] = None,
        allow_family_sync: Optional[bool] = None
    ) -> bool:
        clauses = []
        params = []
        if show_account_in_family is not None:
            clauses.append("show_account_in_family = ?")
            params.append(1 if show_account_in_family else 0)
        if allow_family_uploads is not None:
            clauses.append("allow_family_uploads = ?")
            params.append(1 if allow_family_uploads else 0)
        if allow_family_playlists is not None:
            clauses.append("allow_family_playlists = ?")
            params.append(1 if allow_family_playlists else 0)
        if allow_family_sync is not None:
            clauses.append("allow_family_sync = ?")
            params.append(1 if allow_family_sync else 0)

        if not clauses:
            return True

        clauses.append("updated_at = CURRENT_TIMESTAMP")
        params.extend([family_id, user_id])

        async with self.get_connection() as db:
            cursor = await db.execute(
                f"UPDATE family_members SET {', '.join(clauses)} WHERE family_id = ? AND user_id = ?",
                tuple(params)
            )
            await db.commit()
            return cursor.rowcount > 0

    async def update_family_member_role(self, family_id: str, user_id: str, role: str) -> bool:
        async with self.get_connection() as db:
            cursor = await db.execute(
                "UPDATE family_members SET role = ?, updated_at = CURRENT_TIMESTAMP WHERE family_id = ? AND user_id = ?",
                (role, family_id, user_id)
            )
            await db.commit()
            return cursor.rowcount > 0

    async def remove_family_member(self, family_id: str, user_id: str) -> bool:
        """Remove member from family without deleting user or user's YTM data (Section 28)."""
        async with self.get_connection() as db:
            cursor = await db.execute(
                "DELETE FROM family_members WHERE family_id = ? AND user_id = ?",
                (family_id, user_id)
            )
            await db.commit()
            return cursor.rowcount > 0

    # --- Family Invitations (Section 27) ---

    async def create_family_invitation(
        self,
        family_id: str,
        created_by_user_id: str,
        role: str = "MEMBER",
        ttl_hours: int = 48
    ) -> FamilyInvitation:
        token = secrets.token_urlsafe(32)
        inv_id = f"finv_{secrets.token_hex(8)}"
        now = datetime.now(timezone.utc)
        expires_at = (now + timedelta(hours=ttl_hours)).isoformat()

        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO family_invitations (id, family_id, token, role, created_by_user_id, created_at, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (inv_id, family_id, token, role, created_by_user_id, now.isoformat(), expires_at)
            )
            await db.commit()

        return FamilyInvitation(
            id=inv_id,
            family_id=family_id,
            token=token,
            role=FamilyRole(role),
            created_by_user_id=created_by_user_id,
            created_at=now.isoformat(),
            expires_at=expires_at,
            is_expired=False
        )

    async def get_family_invitation_by_token(self, token: str) -> Optional[FamilyInvitation]:
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM family_invitations WHERE token = ?",
                (token,)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                now_iso = datetime.now(timezone.utc).isoformat()
                is_exp = bool(data.get("accepted_at")) or (data["expires_at"] < now_iso)
                return FamilyInvitation(
                    id=data["id"],
                    family_id=data["family_id"],
                    token=data["token"],
                    role=FamilyRole(data["role"]),
                    created_by_user_id=data["created_by_user_id"],
                    created_at=data.get("created_at"),
                    expires_at=data["expires_at"],
                    accepted_at=data.get("accepted_at"),
                    accepted_by_user_id=data.get("accepted_by_user_id"),
                    is_expired=is_exp
                )

    async def accept_family_invitation(self, token: str, user_id: str) -> FamilyMember:
        inv = await self.get_family_invitation_by_token(token)
        if not inv:
            raise ValueError("Invalid or expired invitation token.")
        if inv.is_expired:
            raise ValueError("Invitation has expired or has already been used.")

        # Check if already a member
        existing = await self.get_family_member(inv.family_id, user_id)
        if existing:
            raise ValueError("You are already a member of this family.")

        now_iso = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            await db.execute(
                "UPDATE family_invitations SET accepted_at = ?, accepted_by_user_id = ? WHERE id = ?",
                (now_iso, user_id, inv.id)
            )
            await db.commit()

        return await self.add_family_member(
            family_id=inv.family_id,
            user_id=user_id,
            role=inv.role.value
        )

    async def list_family_invitations(self, family_id: str) -> list[FamilyInvitation]:
        now_iso = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM family_invitations WHERE family_id = ? AND accepted_at IS NULL AND expires_at >= ? ORDER BY created_at DESC",
                (family_id, now_iso)
            ) as cursor:
                rows = await cursor.fetchall()
                return [
                    FamilyInvitation(
                        id=row["id"],
                        family_id=row["family_id"],
                        token=row["token"],
                        role=FamilyRole(row["role"]),
                        created_by_user_id=row["created_by_user_id"],
                        created_at=row["created_at"],
                        expires_at=row["expires_at"],
                        accepted_at=row["accepted_at"],
                        accepted_by_user_id=row["accepted_by_user_id"],
                        is_expired=False
                    )
                    for row in rows
                ]

    async def revoke_family_invitation(self, family_id: str, invitation_id: str) -> bool:
        async with self.get_connection() as db:
            cursor = await db.execute(
                "DELETE FROM family_invitations WHERE family_id = ? AND id = ?",
                (family_id, invitation_id)
            )
            await db.commit()
            return cursor.rowcount > 0

    # --- Account Selection & Authorization (Sections 9, 23, 24) ---

    async def get_permitted_family_accounts(self, user_id: str) -> list[dict]:
        """Return list of accounts the caller can select or view (Section 9, 23)."""
        items = []
        async with self.get_connection() as db:
            # 1. Caller's own account
            async with db.execute(
                """
                SELECT u.id as user_id, u.username, y.id as account_id, y.account_name, y.status as ytm_status
                FROM users u
                LEFT JOIN ytm_accounts y ON u.id = y.user_id
                WHERE u.id = ?
                """,
                (user_id,)
            ) as cursor:
                self_row = await cursor.fetchone()
                if self_row:
                    items.append({
                        "user_id": self_row["user_id"],
                        "account_id": self_row["account_id"],
                        "username": self_row["username"],
                        "is_self": True,
                        "ytm_connected": self_row["ytm_status"] == "CONNECTED",
                        "account_name": self_row["account_name"],
                        "allow_family_uploads": True,
                        "allow_family_playlists": True,
                        "allow_family_sync": True
                    })

            # 2. Permitted family accounts
            async with db.execute(
                """
                SELECT DISTINCT fm.user_id, u.username, y.id as account_id, y.account_name, y.status as ytm_status,
                       fm.allow_family_uploads, fm.allow_family_playlists, fm.allow_family_sync
                FROM family_members fm
                JOIN users u ON fm.user_id = u.id
                LEFT JOIN ytm_accounts y ON u.id = y.user_id
                WHERE fm.family_id IN (SELECT family_id FROM family_members WHERE user_id = ? AND status = 'ACTIVE')
                  AND fm.user_id != ?
                  AND fm.show_account_in_family = 1
                  AND fm.status = 'ACTIVE'
                """,
                (user_id, user_id)
            ) as cursor:
                rows = await cursor.fetchall()
                for row in rows:
                    items.append({
                        "user_id": row["user_id"],
                        "account_id": row["account_id"],
                        "username": row["username"],
                        "is_self": False,
                        "ytm_connected": row["ytm_status"] == "CONNECTED",
                        "account_name": row["account_name"],
                        "allow_family_uploads": bool(row["allow_family_uploads"]),
                        "allow_family_playlists": bool(row["allow_family_playlists"]),
                        "allow_family_sync": bool(row["allow_family_sync"])
                    })
        return items

    async def validate_upload_destination_permission(self, caller_user_id: str, destination_user_id: str) -> tuple[bool, Optional[str]]:
        """Strict server-side validation of upload destination permissions (Sections 15, 24)."""
        if caller_user_id == destination_user_id:
            acc = await self.get_ytm_account(caller_user_id)
            if not acc or acc.status != "CONNECTED":
                return False, "Your YouTube Music account is not connected."
            return True, None

        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT fm_dest.allow_family_uploads, y.status as ytm_status
                FROM family_members fm_caller
                JOIN family_members fm_dest ON fm_caller.family_id = fm_dest.family_id
                LEFT JOIN ytm_accounts y ON fm_dest.user_id = y.user_id
                WHERE fm_caller.user_id = ? AND fm_dest.user_id = ?
                  AND fm_caller.status = 'ACTIVE' AND fm_dest.status = 'ACTIVE'
                LIMIT 1
                """,
                (caller_user_id, destination_user_id)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return False, "Destination user is not in your family."
                if not row["allow_family_uploads"]:
                    return False, "Destination user has disabled family uploads."
                if row["ytm_status"] != "CONNECTED":
                    return False, "Destination YouTube Music account is not connected."
                return True, None

    async def check_track_duplicate_for_user(self, music_file_id: int, user_id: str) -> dict:
        """Duplicate detection strictly isolated to destination user (Section 34)."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT 1 FROM sync_jobs WHERE music_file_id = ? AND user_id = ? AND status IN ('completed', 'verified', 'VERIFIED')
                LIMIT 1
                """,
                (music_file_id, user_id)
            ) as cursor:
                matched = (await cursor.fetchone()) is not None

            async with db.execute(
                "SELECT status, error FROM sync_jobs WHERE music_file_id = ? AND user_id = ? ORDER BY id DESC LIMIT 1",
                (music_file_id, user_id)
            ) as cursor:
                job_row = await cursor.fetchone()
                status = "already_uploaded" if matched else (job_row["status"] if job_row else "not_uploaded")
                err = job_row["error"] if job_row else None

            return {
                "is_uploaded": matched or (status in ("completed", "verified", "VERIFIED")),
                "status": status,
                "error": err
            }

    async def get_family_upload_history(self, family_id: str, caller_user_id: str, limit: int = 50) -> list[dict]:
        """Combined family upload history respecting member privacy (Section 17)."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT sj.id, sj.music_file_id, mf.filename, mf.title, mf.artist,
                       sj.user_id as destination_user_id, u_dest.username as destination_username,
                       sj.requested_by_user_id, u_req.username as requested_by_username,
                       sj.status, sj.error, sj.started_at as created_at, sj.completed_at
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                JOIN users u_dest ON sj.user_id = u_dest.id
                LEFT JOIN users u_req ON sj.requested_by_user_id = u_req.id
                WHERE (sj.family_id = ? OR sj.user_id IN (
                    SELECT user_id FROM family_members WHERE family_id = ? AND show_account_in_family = 1
                ))
                ORDER BY sj.id DESC LIMIT ?
                """,
                (family_id, family_id, limit)
            ) as cursor:
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]

    async def get_family_queue_grouped(self, family_id: str, caller_user_id: str) -> list[dict]:
        """Group upload queue jobs by track and destination (Section 33)."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT sj.id as job_id, sj.music_file_id, mf.filename, mf.title, mf.artist,
                       sj.user_id as destination_user_id, u_dest.username as destination_username,
                       sj.status, sj.attempts, sj.error
                FROM sync_jobs sj
                JOIN music_files mf ON sj.music_file_id = mf.id
                JOIN users u_dest ON sj.user_id = u_dest.id
                WHERE (sj.family_id = ? OR sj.user_id IN (
                    SELECT user_id FROM family_members WHERE family_id = ? AND show_account_in_family = 1
                ))
                AND sj.status IN ('queued', 'uploading', 'verifying', 'PENDING', 'DOWNLOADING', 'VERIFYING')
                ORDER BY sj.id ASC
                """,
                (family_id, family_id)
            ) as cursor:
                rows = await cursor.fetchall()
                grouped = {}
                for r in rows:
                    fid = r["music_file_id"]
                    if fid not in grouped:
                        grouped[fid] = {
                            "music_file_id": fid,
                            "filename": r["filename"],
                            "title": r["title"],
                            "artist": r["artist"],
                            "destinations": []
                        }
                    grouped[fid]["destinations"].append({
                        "job_id": r["job_id"],
                        "destination_user_id": r["destination_user_id"],
                        "destination_username": r["destination_username"],
                        "status": r["status"],
                        "attempts": r["attempts"],
                        "error": r["error"]
                    })
                return list(grouped.values())

    async def get_family_permitted_sync_members(self, family_id: str) -> list[FamilyMember]:
        """Find members permitted to participate in Family Sync (Section 18)."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT fm.*, u.username
                FROM family_members fm
                JOIN users u ON fm.user_id = u.id
                JOIN ytm_accounts y ON u.id = y.user_id
                WHERE fm.family_id = ? AND fm.allow_family_sync = 1 AND fm.status = 'ACTIVE' AND y.status = 'CONNECTED'
                """,
                (family_id,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [
                    FamilyMember(
                        id=row["id"],
                        family_id=row["family_id"],
                        user_id=row["user_id"],
                        username=row["username"],
                        role=FamilyRole(row["role"]),
                        status=FamilyMemberStatus(row["status"]),
                        show_account_in_family=bool(row["show_account_in_family"]),
                        allow_family_uploads=bool(row["allow_family_uploads"]),
                        allow_family_playlists=bool(row["allow_family_playlists"]),
                        allow_family_sync=bool(row["allow_family_sync"]),
                        created_at=row["created_at"],
                        updated_at=row["updated_at"]
                    )
                    for row in rows
                ]

    async def get_family_permitted_playlists(self, family_id: str, caller_user_id: str) -> list[dict]:
        """Read-only view of shared family playlists (Section 19)."""
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT CAST(rp.id AS TEXT) as playlist_id,
                       rp.destination_playlist_id,
                       rp.source_playlist_id,
                       COALESCE(rp.destination_playlist_name, rp.source_playlist_name) as name,
                       COALESCE(rp.destination_playlist_name, rp.source_playlist_name) as title,
                       rp.user_id as owner_user_id,
                       u.username as owner_username,
                       COALESCE(
                           (SELECT track_count FROM replicated_playlist_snapshots WHERE replicated_playlist_id = rp.id ORDER BY id DESC LIMIT 1),
                           0
                       ) as track_count
                FROM replicated_playlists rp
                JOIN users u ON rp.user_id = u.id
                WHERE COALESCE(rp.shared_with_family, 1) = 1
                  AND rp.user_id IN (
                    SELECT user_id FROM family_members WHERE family_id = ? AND allow_family_playlists = 1 AND status = 'ACTIVE'
                )
                ORDER BY rp.created_at DESC
                """,
                (family_id,)
            ) as cursor:
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]

    async def create_multi_account_playlists(
        self,
        playlist_name: str,
        destination_user_ids: list[str],
        created_by_user_id: str,
        family_id: Optional[str] = None
    ) -> list[dict]:
        """Create independent playlist on each permitted destination account (Section 35)."""
        results = []
        for dest_id in destination_user_ids:
            allowed, _ = await self.validate_upload_destination_permission(created_by_user_id, dest_id)
            if not allowed:
                continue
            rep = await self.create_replicated_playlist(
                name=playlist_name,
                source_type="uploaded_only",
                source_playlist_id=f"family_{family_id or 'shared'}_{secrets.token_hex(4)}",
                destination_playlist_id=f"ytm_{secrets.token_hex(6)}",
                user_id=dest_id
            )
            results.append({
                "destination_user_id": dest_id,
                "replicated_playlist_id": rep.id,
                "name": rep.name
            })
        return results

    async def set_playlist_family_sharing(self, replicated_id: int, shared: bool = False) -> bool:
        """Update shared_with_family flag on replicated_playlists."""
        async with self.get_connection() as db:
            cursor = await db.execute(
                "UPDATE replicated_playlists SET shared_with_family = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (1 if shared else 0, replicated_id)
            )
            await db.commit()
            return cursor.rowcount > 0
