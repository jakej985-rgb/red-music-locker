"""Router module for Settings & Status endpoints."""
import logging

from fastapi import APIRouter, Depends

from ..models import (
    DashboardStats,
    User,
    UserSettings,
    UserSettingsUpdate
)
from ..database import db
from ..dependencies import require_authenticated_user
from ..scanner import scanner
from ..ytm_client import ytm_client
from ..uploader import queue_manager

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Settings & Status"])

@router.get("/api/settings", response_model=UserSettings)
async def get_user_settings(current_user: User = Depends(require_authenticated_user)):
    """Get settings for current user."""
    return await db.get_user_settings(current_user.id)


@router.put("/api/settings", response_model=UserSettings)
async def update_user_settings_put(req: UserSettingsUpdate, current_user: User = Depends(require_authenticated_user)):
    """Update settings for current user."""
    return await db.update_user_settings(current_user.id, req)


@router.post("/api/settings")
async def update_user_settings_post(req: UserSettingsUpdate, current_user: User = Depends(require_authenticated_user)):
    """Update settings for current user via POST (backward compatible)."""
    await db.update_user_settings(current_user.id, req)
    return {"status": "success"}


@router.get("/api/status", response_model=DashboardStats)
async def get_dashboard_status(current_user: User = Depends(require_authenticated_user)):
    counts = await db.get_dashboard_counts(user_id=current_user.id)
    conn = await ytm_client.test_connection(user_id=current_user.id)
    return DashboardStats(
        ytm_connected=conn["connected"],
        account_name=conn["user_name"],
        local_songs_count=counts["local_songs_count"],
        ytm_uploads_count=counts["ytm_uploads_count"],
        missing_count=counts["missing_count"],
        uploaded_count=counts["uploaded_count"],
        failed_count=counts["failed_count"],
        in_queue_count=counts["in_queue_count"],
        is_scanning=scanner.is_scanning,
        is_uploading=queue_manager.is_running,
    )


