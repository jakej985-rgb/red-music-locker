"""Database mixin for user accounts, application sessions, user settings, and YTM accounts."""
import aiosqlite
import json
import logging
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional, Any, Union, Dict, List, Tuple, Set
from ..config import settings, AUTH_DIR, DEFAULT_DATA_DIR, USERS_DIR
from ..models import (
    User, UserCreate, UserUpdate, UserRole,
    AppSession, YouTubeMusicAccount, YtmAccountStatus,
    UserSettings, UserSettingsUpdate, SyncJob, YtmUpload
)
from ..security import (
    hash_password, verify_password, validate_user_id,
    get_user_subpath, encrypt_auth_data
)
from .base import logger


class UserDbMixin:
    """User accounts, sessions, YTM account credentials, and settings."""
    async def _ensure_admin_bootstrapped(self):
        """Bootstrap default admin account and migrate single-user installation if no users exist."""
        count = await self.count_users()
        if count > 0:
            return

        admin_id = str(uuid.uuid4())
        admin_username = os.environ.get("YTM_SYNC_ADMIN_USER", "admin").strip()
        admin_password = os.environ.get("YTM_SYNC_ADMIN_PASSWORD", "").strip()

        if not admin_password:
            key_file = AUTH_DIR / "admin_password.txt"
            if key_file.exists():
                admin_password = key_file.read_text(encoding="utf-8").strip()
            if not admin_password:
                admin_password = secrets.token_urlsafe(12)
                flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
                fd = os.open(str(key_file), flags, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(admin_password + "\n")
                try:
                    os.chmod(str(key_file), 0o600)
                except OSError:
                    pass
                logger.info(f"Generated initial admin credentials in {key_file}")

        pwd_hash = hash_password(admin_password)
        admin_user = await self.create_user(
            username=admin_username,
            password_hash=pwd_hash,
            role=UserRole.ADMIN,
            is_active=True,
            user_id=admin_id
        )
        logger.info(f"Bootstrapped default admin user '{admin_username}' (ID: {admin_id})")

        # Backfill existing single-user records to this admin
        async with self.get_connection() as db:
            await db.execute("UPDATE replicated_playlists SET user_id = ? WHERE user_id IS NULL", (admin_id,))
            await db.execute("UPDATE ytm_uploads SET user_id = ? WHERE user_id IS NULL", (admin_id,))
            await db.execute("UPDATE sync_jobs SET user_id = ? WHERE user_id IS NULL", (admin_id,))
            await db.execute("UPDATE needs_help_tracks SET user_id = ? WHERE user_id IS NULL", (admin_id,))
            await db.commit()

        # Migrate existing global authentication if present (Phase V)
        legacy_auth = settings.auth_file
        if not legacy_auth.exists() and settings.auth_dir == AUTH_DIR:
            fallback = DEFAULT_DATA_DIR / "headers_auth.json"
            if fallback.exists():
                legacy_auth = fallback

        if legacy_auth.exists() and legacy_auth.stat().st_size > 10:
            backup_file = legacy_auth.with_name(legacy_auth.name + ".migrated_backup")
            deprecate_file = legacy_auth.with_name(legacy_auth.name + ".migrated")
            try:
                import shutil
                # Step 1: Create recoverable backup before touching
                shutil.copy2(str(legacy_auth), str(backup_file))
                logger.info(f"Phase V: Created safety backup of legacy authentication at {backup_file}")

                # Step 2: Move/copy credentials into user-specific storage
                user_auth_dir = get_user_subpath(admin_id, "auth")
                user_auth_file = user_auth_dir / "headers_auth.json"
                raw_bytes = legacy_auth.read_bytes()
                
                # Encrypt into user storage
                enc_data = encrypt_auth_data(raw_bytes)
                flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
                fd = os.open(str(user_auth_file), flags, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(enc_data)
                try:
                    os.chmod(str(user_auth_file), 0o600)
                except OSError:
                    pass

                # Step 3: Verify connection
                from ..ytm_client import ytm_client
                conn_test = await ytm_client.test_connection(user_id=admin_id)
                
                if conn_test.get("connected"):
                    acc_name = conn_test.get("user_name") or "Migrated Account"
                    await self.create_or_update_ytm_account(
                        user_id=admin_id,
                        account_name=acc_name,
                        auth_reference=str(user_auth_file),
                        status=YtmAccountStatus.CONNECTED
                    )
                    # Step 4: Deprecate old global authentication by renaming to .migrated (not deleted silently!)
                    shutil.move(str(legacy_auth), str(deprecate_file))
                    logger.info(
                        f"Phase V: Successfully verified and migrated legacy global authentication to user '{admin_id}' ({acc_name}). "
                        f"Old global authentication preserved at {deprecate_file}."
                    )
                else:
                    await self.create_or_update_ytm_account(
                        user_id=admin_id,
                        account_name="Unverified Migrated Account",
                        auth_reference=str(user_auth_file),
                        status=YtmAccountStatus.DISCONNECTED
                    )
                    logger.warning(
                        f"Phase V: Legacy authentication copied to user '{admin_id}', but connection test failed: {conn_test.get('message')}. "
                        f"Preserving original global file at {legacy_auth}."
                    )
            except Exception as e:
                logger.error(f"Phase V: Failed during legacy authentication migration: {e}", exc_info=True)

    async def create_user(
        self,
        username: Union[str, UserCreate],
        password_hash: Optional[str] = None,
        role: Union[UserRole, str] = UserRole.USER,
        is_active: bool = True,
        user_id: Optional[str] = None
    ) -> User:
        if isinstance(username, UserCreate):
            req = username
            clean_username = req.username.strip()
            password_hash = hash_password(req.password)
            role = req.role
        else:
            clean_username = str(username).strip()
            if not password_hash:
                raise ValueError("password_hash is required when username is a string")
        uid = user_id or str(uuid.uuid4())
        role_str = role.value if isinstance(role, UserRole) else str(role).upper()

        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO users (id, username, password_hash, role, is_active)
                VALUES (?, ?, ?, ?, ?)
                """,
                (uid, clean_username, password_hash, role_str, 1 if is_active else 0)
            )
            await db.commit()
        return await self.get_user_by_id(uid)

    async def get_user_by_id(self, user_id: str) -> Optional[User]:
        async with self.get_connection() as db:
            async with db.execute("SELECT * FROM users WHERE id = ?", (user_id,)) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                data["is_active"] = bool(data.get("is_active", 1))
                return User(**data)

    async def get_user_by_username(self, username: str) -> Optional[User]:
        clean = username.strip()
        async with self.get_connection() as db:
            async with db.execute("SELECT * FROM users WHERE username = ? COLLATE NOCASE", (clean,)) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                data["is_active"] = bool(data.get("is_active", 1))
                return User(**data)

    async def list_users(self) -> list[User]:
        async with self.get_connection() as db:
            async with db.execute("SELECT * FROM users ORDER BY created_at ASC") as cursor:
                rows = await cursor.fetchall()
                results = []
                for row in rows:
                    data = dict(row)
                    data["is_active"] = bool(data.get("is_active", 1))
                    results.append(User(**data))
                return results

    async def update_user(
        self,
        user_id: str,
        update_or_role: Optional[Union[UserUpdate, UserRole, str]] = None,
        is_active: Optional[bool] = None,
        password_hash: Optional[str] = None,
        role: Optional[Union[UserRole, str]] = None
    ) -> Optional[User]:
        if isinstance(update_or_role, UserUpdate):
            req = update_or_role
            if req.role is not None:
                role = req.role
            if req.is_active is not None:
                is_active = req.is_active
            if req.password is not None:
                password_hash = hash_password(req.password)
        elif isinstance(update_or_role, (UserRole, str)):
            role = update_or_role

        clauses = []
        params = []
        if role is not None:
            clauses.append("role = ?")
            params.append(role.value if isinstance(role, UserRole) else str(role).upper())
        if is_active is not None:
            clauses.append("is_active = ?")
            params.append(1 if is_active else 0)
        if password_hash is not None:
            clauses.append("password_hash = ?")
            params.append(password_hash)

        if not clauses:
            return await self.get_user_by_id(user_id)

        clauses.append("updated_at = CURRENT_TIMESTAMP")
        params.append(user_id)

        async with self.get_connection() as db:
            await db.execute(f"UPDATE users SET {', '.join(clauses)} WHERE id = ?", tuple(params))
            await db.commit()
        return await self.get_user_by_id(user_id)

    async def update_last_login(self, user_id: str):
        now = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            await db.execute("UPDATE users SET last_login_at = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (now, user_id))
            await db.commit()

    async def delete_user(self, user_id: str) -> bool:
        """Permanently delete user and all user-owned database records (Phase U)."""
        async with self.get_connection() as db:
            # 1. Clean up replicated playlist snapshots and events for playlists owned by this user
            await db.execute(
                """
                DELETE FROM replicated_playlist_snapshots 
                WHERE replicated_playlist_id IN (SELECT id FROM replicated_playlists WHERE user_id = ?)
                """,
                (user_id,)
            )
            await db.execute(
                """
                DELETE FROM replicated_playlist_events 
                WHERE replicated_playlist_id IN (SELECT id FROM replicated_playlists WHERE user_id = ?)
                """,
                (user_id,)
            )
            await db.execute("DELETE FROM replicated_playlists WHERE user_id = ?", (user_id,))
            
            # 2. Clean up uploads, sync jobs, needs_help_tracks owned by this user
            await db.execute("DELETE FROM ytm_uploads WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM sync_jobs WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM needs_help_tracks WHERE user_id = ?", (user_id,))

            # 3. Clean up user settings, ytm accounts, sessions, and family data
            await db.execute("DELETE FROM user_settings WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM ytm_accounts WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM app_sessions WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM family_members WHERE user_id = ?", (user_id,))
            await db.execute("DELETE FROM family_invitations WHERE created_by_user_id = ? OR accepted_by_user_id = ?", (user_id, user_id))
            await db.execute("DELETE FROM families WHERE owner_user_id = ?", (user_id,))

            # 4. Delete user record
            cursor = await db.execute("DELETE FROM users WHERE id = ?", (user_id,))
            await db.commit()
            return cursor.rowcount > 0

    async def count_users(self) -> int:
        async with self.get_connection() as db:
            async with db.execute("SELECT COUNT(*) FROM users") as cursor:
                row = await cursor.fetchone()
                return row[0] if row else 0

    async def count_admins(self) -> int:
        """Count active administrator accounts."""
        async with self.get_connection() as db:
            async with db.execute("SELECT COUNT(*) FROM users WHERE role = 'ADMIN' AND is_active = 1") as cursor:
                row = await cursor.fetchone()
                return row[0] if row else 0

    # --- Session Management (Phase F) ---

    async def create_app_session(self, user_id: str, duration_seconds: int = 7 * 86400) -> AppSession:
        token = secrets.token_urlsafe(32)
        now = datetime.now(timezone.utc)
        expires_at = (now + timedelta(seconds=duration_seconds)).isoformat()
        now_str = now.isoformat()

        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO app_sessions (token, user_id, created_at, expires_at)
                VALUES (?, ?, ?, ?)
                """,
                (token, user_id, now_str, expires_at)
            )
            await db.commit()
        return AppSession(token=token, user_id=user_id, created_at=now_str, expires_at=expires_at)

    async def get_app_session(self, token: str) -> Optional[AppSession]:
        if not token:
            return None
        async with self.get_connection() as db:
            async with db.execute("SELECT * FROM app_sessions WHERE token = ?", (token,)) as cursor:
                row = await cursor.fetchone()
                return AppSession(**dict(row)) if row else None

    async def get_user_by_session_token(self, token: str) -> Optional[User]:
        if not token:
            return None
        now_iso = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            async with db.execute(
                """
                SELECT u.* FROM users u
                INNER JOIN app_sessions s ON u.id = s.user_id
                WHERE s.token = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.is_active = 1
                """,
                (token, now_iso)
            ) as cursor:
                row = await cursor.fetchone()
                if not row:
                    return None
                data = dict(row)
                data["is_active"] = bool(data.get("is_active", 1))
                return User(**data)

    async def revoke_app_session(self, token: str) -> bool:
        if not token:
            return False
        now_iso = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            cursor = await db.execute("UPDATE app_sessions SET revoked_at = ? WHERE token = ?", (now_iso, token))
            await db.commit()
            return cursor.rowcount > 0

    async def revoke_all_user_sessions(self, user_id: str):
        now_iso = datetime.now(timezone.utc).isoformat()
        async with self.get_connection() as db:
            await db.execute("UPDATE app_sessions SET revoked_at = ? WHERE user_id = ?", (now_iso, user_id))
            await db.commit()

    # --- YouTube Music Account Management (Phase H & J) ---

    async def create_or_update_ytm_account(
        self,
        user_id: str,
        account_name: Optional[str] = None,
        account_identifier: Optional[str] = None,
        auth_reference: Optional[str] = None,
        encrypted_credentials: Optional[str] = None,
        status: Union[YtmAccountStatus, str] = YtmAccountStatus.CONNECTED
    ) -> YouTubeMusicAccount:
        now_iso = datetime.now(timezone.utc).isoformat()
        status_str = status.value if isinstance(status, YtmAccountStatus) else str(status).upper()

        existing = await self.get_ytm_account_by_user_id(user_id)
        async with self.get_connection() as db:
            if existing:
                await db.execute(
                    """
                    UPDATE ytm_accounts
                    SET account_name = COALESCE(?, account_name),
                        account_identifier = COALESCE(?, account_identifier),
                        auth_reference = COALESCE(?, auth_reference),
                        encrypted_credentials = COALESCE(?, encrypted_credentials),
                        status = ?,
                        updated_at = CURRENT_TIMESTAMP,
                        last_verified_at = CURRENT_TIMESTAMP
                    WHERE user_id = ?
                    """,
                    (account_name, account_identifier, auth_reference, encrypted_credentials, status_str, user_id)
                )
                account_id = existing.id
            else:
                account_id = str(uuid.uuid4())
                await db.execute(
                    """
                    INSERT INTO ytm_accounts (
                        id, user_id, account_name, account_identifier,
                        auth_reference, encrypted_credentials, status,
                        created_at, updated_at, last_verified_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """,
                    (account_id, user_id, account_name, account_identifier, auth_reference, encrypted_credentials, status_str)
                )
            await db.commit()
        return await self.get_ytm_account_by_user_id(user_id)

    async def get_ytm_account_by_user_id(self, user_id: str) -> Optional[YouTubeMusicAccount]:
        async with self.get_connection() as db:
            async with db.execute("SELECT * FROM ytm_accounts WHERE user_id = ?", (user_id,)) as cursor:
                row = await cursor.fetchone()
                return YouTubeMusicAccount(**dict(row)) if row else None

    get_ytm_account = get_ytm_account_by_user_id

    async def delete_ytm_account_for_user(self, user_id: str) -> bool:
        async with self.get_connection() as db:
            cursor = await db.execute("DELETE FROM ytm_accounts WHERE user_id = ?", (user_id,))
            await db.commit()
            return cursor.rowcount > 0

    # --- User-Specific Settings Management (Phase Q) ---

    async def get_user_setting(self, user_id: str, key: str, default: Any = None) -> Any:
        async with self.get_connection() as db:
            async with db.execute("SELECT value FROM user_settings WHERE user_id = ? AND key = ?", (user_id, key)) as cursor:
                row = await cursor.fetchone()
                if row:
                    try:
                        return json.loads(row["value"])
                    except Exception:
                        return row["value"]
                return default

    async def set_user_setting(self, user_id: str, key: str, value: Any):
        val_str = json.dumps(value) if not isinstance(value, str) else value
        async with self.get_connection() as db:
            await db.execute(
                """
                INSERT INTO user_settings (user_id, key, value)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value
                """,
                (user_id, key, val_str)
            )
            await db.commit()

    async def get_user_settings(self, user_id: str) -> UserSettings:
        sync_enabled = await self.get_user_setting(user_id, "sync_enabled", default=True)
        sync_interval = await self.get_user_setting(user_id, "sync_interval_seconds", default=300)
        auto_upload = await self.get_user_setting(user_id, "auto_upload", default=False)
        download_location = await self.get_user_setting(user_id, "download_location", default=None)
        music_folders = await self.get_user_setting(user_id, "music_folders", default=[])
        scan_interval = await self.get_user_setting(user_id, "scan_interval_minutes", default=15)
        verify_uploads = await self.get_setting("verify_uploads", default=True)
        allow_automatic_replacement = await self.get_setting("allow_automatic_replacement", default=settings.allow_automatic_replacement)
        return UserSettings(
            user_id=user_id,
            sync_enabled=bool(sync_enabled),
            sync_interval_seconds=int(sync_interval),
            auto_upload=bool(auto_upload),
            download_location=download_location,
            music_folders=list(music_folders),
            scan_interval_minutes=int(scan_interval),
            verify_uploads=bool(verify_uploads),
            allow_automatic_replacement=bool(allow_automatic_replacement)
        )

    async def update_user_settings(self, user_id: str, updates: Union[UserSettingsUpdate, dict[str, Any]]) -> UserSettings:
        items = updates.model_dump(exclude_unset=True) if hasattr(updates, "model_dump") else dict(updates)
        for k, v in items.items():
            if v is not None:
                if k == "allow_automatic_replacement":
                    await self.set_setting("allow_automatic_replacement", v)
                    settings.allow_automatic_replacement = v
                elif k == "verify_uploads":
                    await self.set_setting("verify_uploads", v)
                else:
                    await self.set_user_setting(user_id, k, v)
        return await self.get_user_settings(user_id)

    # --- User-Scoped Queries (Phase M) ---

    async def get_user_sync_jobs(self, user_id: str, limit: int = 50) -> list[SyncJob]:
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM sync_jobs WHERE user_id = ? ORDER BY id DESC LIMIT ?",
                (user_id, limit)
            ) as cursor:
                rows = await cursor.fetchall()
                return [SyncJob(**dict(row)) for row in rows]

    async def get_user_uploads(self, user_id: str, limit: int = 50) -> list[YtmUpload]:
        async with self.get_connection() as db:
            async with db.execute(
                "SELECT * FROM ytm_uploads WHERE user_id = ? ORDER BY id DESC LIMIT ?",
                (user_id, limit)
            ) as cursor:
                rows = await cursor.fetchall()
                return [YtmUpload(**dict(row)) for row in rows]


    # ==========================================
    # Family Mode & Multi-Account Methods (Sections 1-40)
    # ==========================================


