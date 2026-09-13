"""Router module for Users & Admin endpoints."""
import logging

from typing import Optional
import shutil

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from ..models import (
    User,
    UserRole,
    UserResponse,
    UserCreate,
    UserUpdate,
    Family,
    SelectableAccountItem
)
from ..database import db
from ..config import settings
from ..dependencies import require_admin, require_authenticated_user
from ..security import verify_password
from ..ytm_client import ytm_client

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Users & Admin"])

@router.get("/api/admin/users", response_model=list[UserResponse])
async def list_users_admin(admin: User = Depends(require_admin)):
    """Admin-only: list all application users."""
    users = await db.list_users()
    return [
        UserResponse(
            id=u.id,
            username=u.username,
            role=u.role,
            is_active=u.is_active,
            created_at=u.created_at,
            last_login_at=u.last_login_at,
        )
        for u in users
    ]


@router.post("/api/admin/users", response_model=UserResponse)
async def create_user_admin(req: UserCreate, admin: User = Depends(require_admin)):
    """Admin-only: create a new application user."""
    existing = await db.get_user_by_username(req.username)
    if existing:
        raise HTTPException(status_code=409, detail=f"Username '{req.username}' already exists")
    user = await db.create_user(req)
    return UserResponse(
        id=user.id,
        username=user.username,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
        last_login_at=user.last_login_at,
    )


@router.put("/api/admin/users/{user_id}", response_model=UserResponse)
async def update_user_admin(user_id: str, req: UserUpdate, admin: User = Depends(require_admin)):
    """Admin-only: update user details, username, role, or active status."""
    user = await db.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if req.username is not None:
        cleaned = req.username.strip()
        if not cleaned:
            raise HTTPException(status_code=400, detail="Username cannot be empty")
        existing = await db.get_user_by_username(cleaned)
        if existing and existing.id != user_id:
            raise HTTPException(status_code=409, detail=f"Username '{cleaned}' already exists")
        req.username = cleaned
    updated = await db.update_user(user_id, req)
    if not updated:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse(
        id=updated.id,
        username=updated.username,
        role=updated.role,
        is_active=updated.is_active,
        created_at=updated.created_at,
        last_login_at=updated.last_login_at,
    )


class UserDeleteRequest(BaseModel):
    password: Optional[str] = None

@router.delete("/api/admin/users/{user_id}")
async def delete_user_admin(
    user_id: str,
    confirm: bool = Query(False),
    admin: User = Depends(require_admin)
):
    """Admin-only: delete an application user with required confirmation."""
    if not confirm:
        raise HTTPException(status_code=400, detail="User deletion must be confirmed with confirm=true")
    if admin.id == user_id:
        raise HTTPException(status_code=400, detail="Cannot delete your own admin account")
    user = await db.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role == UserRole.ADMIN:
        admin_count = await db.count_admins()
        if admin_count <= 1:
            raise HTTPException(status_code=400, detail="Cannot delete the last administrator")

    # Clean up user's local config folder
    user_dir = settings.config_dir / "users" / user_id
    if user_dir.exists():
        shutil.rmtree(user_dir, ignore_errors=True)

    await db.delete_user(user_id)
    ytm_client.disconnect_user(user_id)
    logger.info(f"User {user_id} deleted permanently by admin {admin.id}")
    return {"status": "ok", "message": f"User {user_id} deleted"}


@router.delete("/api/users/me")
async def delete_current_user(
    confirm: bool = Query(False),
    req: Optional[UserDeleteRequest] = None,
    current_user: User = Depends(require_authenticated_user)
):
    """Self-delete user account with explicit confirmation."""
    if not confirm:
        raise HTTPException(status_code=400, detail="User deletion must be confirmed with confirm=true")
    if current_user.role == UserRole.ADMIN:
        admin_count = await db.count_admins()
        if admin_count <= 1:
            raise HTTPException(status_code=400, detail="Cannot delete the last administrator")
    if req and req.password:
        user_db = await db.get_user_by_id(current_user.id)
        if not user_db or not verify_password(req.password, user_db.password_hash):
            raise HTTPException(status_code=401, detail="Invalid password")

    user_id = current_user.id
    user_dir = settings.config_dir / "users" / user_id
    if user_dir.exists():
        shutil.rmtree(user_dir, ignore_errors=True)

    await db.delete_user(user_id)
    ytm_client.disconnect_user(user_id)
    logger.info(f"User {user_id} deleted their own account permanently")
    return {"status": "ok", "message": "Account deleted successfully"}


# ============================================================================
# Family Mode & Multi-Account Endpoints (Sections 1–40)
# ============================================================================

# --- Account Selector Endpoints (Sections 9, 23) ---


@router.get("/api/accounts", response_model=list[SelectableAccountItem])
async def list_selectable_accounts(current_user: User = Depends(require_authenticated_user)):
    """Return list of accounts available to the user (personal + permitted family accounts)."""
    items = await db.get_permitted_family_accounts(current_user.id)
    return [SelectableAccountItem(**item) for item in items]


@router.get("/api/accounts/{account_id}", response_model=SelectableAccountItem)
async def get_selectable_account(account_id: str, current_user: User = Depends(require_authenticated_user)):
    """Get selectable account info if permitted."""
    items = await db.get_permitted_family_accounts(current_user.id)
    for item in items:
        if item.get("account_id") == account_id or item.get("user_id") == account_id:
            return SelectableAccountItem(**item)
    raise HTTPException(status_code=404, detail="Account not found or access denied")


# --- Family Management Endpoints (Sections 1–8, 23, 27–31) ---


