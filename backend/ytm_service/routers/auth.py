"""Router module for Authentication endpoints."""
import logging

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from ..models import (
    AuthSetupRequest,
    ConnectionStatus,
    User,
    UserRole,
    UserResponse,
    UserLoginRequest,
    UserLoginResponse,
    UserUpdate
)
from ..database import db
from ..dependencies import require_authenticated_user
from ..rate_limiter import rate_limit_dependency
from ..security import validate_auth_origin_url, verify_password
from ..ytm_client import ytm_client
from ..auth_service import auth_service
from ..auth_session import AuthStartRequest, AuthStartResponse, AuthSessionResponse, AuthCompleteRequest, AuthCallbackRequest, AuthCancelRequest

logger = logging.getLogger("ytm_sync")

router = APIRouter(tags=["Authentication"])

class ProfileUpdateRequest(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None

@router.put("/api/auth/me", response_model=UserResponse)
async def update_current_user_profile(
    req: ProfileUpdateRequest,
    current_user: User = Depends(require_authenticated_user)
):
    """Update profile of current authenticated user (username, password)."""
    if req.username is not None:
        cleaned = req.username.strip()
        if not cleaned:
            raise HTTPException(status_code=400, detail="Username cannot be empty")
        existing = await db.get_user_by_username(cleaned)
        if existing and existing.id != current_user.id:
            raise HTTPException(status_code=409, detail=f"Username '{cleaned}' already exists")
        req.username = cleaned
    updated = await db.update_user(current_user.id, UserUpdate(username=req.username, password=req.password))
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

@router.post("/api/auth/login", response_model=UserLoginResponse, dependencies=[Depends(rate_limit_dependency(5, 60, "login"))])
async def login(req: UserLoginRequest):
    """Authenticate application user with username and password, returning a secure session token."""
    user = await db.get_user_by_username(req.username)
    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    session = await db.create_app_session(user.id)
    await db.update_last_login(user.id)

    return UserLoginResponse(
        token=session.token,
        expires_at=session.expires_at,
        user=UserResponse(
            id=user.id,
            username=user.username,
            role=user.role,
            is_active=user.is_active,
            created_at=user.created_at,
            last_login_at=user.last_login_at,
        ),
    )


@router.post("/api/auth/logout")
async def logout(request: Request, current_user: User = Depends(require_authenticated_user)):
    """Revoke active application session token."""
    auth_hdr = request.headers.get("Authorization", "")
    if auth_hdr.strip().lower().startswith("bearer "):
        token = auth_hdr.strip().split(" ", 1)[1].strip()
        await db.revoke_app_session(token)
    return {"status": "ok", "message": "Logged out successfully"}


@router.get("/api/auth/me", response_model=UserResponse)
async def get_current_user_profile(current_user: User = Depends(require_authenticated_user)):
    """Get profile of current authenticated user."""
    return UserResponse(
        id=current_user.id,
        username=current_user.username,
        role=current_user.role,
        is_active=current_user.is_active,
        created_at=current_user.created_at,
        last_login_at=current_user.last_login_at,
    )


@router.get("/api/auth/status", response_model=ConnectionStatus)
async def get_auth_status(current_user: User = Depends(require_authenticated_user)):
    res = await ytm_client.test_connection(user_id=current_user.id)
    return ConnectionStatus(
        connected=res["connected"],
        message=res["message"],
        user_name=res.get("user_name")
    )


@router.post("/api/auth/start", response_model=AuthStartResponse, dependencies=[Depends(rate_limit_dependency(10, 60, "auth_start"))])
async def start_auth_session(request: Request, req: Optional[AuthStartRequest] = None, current_user: User = Depends(require_authenticated_user)):
    """Start a new short-lived, single-use authentication session with validated origin."""
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    host = request.headers.get("x-forwarded-host", request.headers.get("host")) or request.url.netloc

    raw_origin = req.origin_url if (req and req.origin_url) else None
    if raw_origin:
        try:
            origin_url = validate_auth_origin_url(raw_origin, request_host=host, request_proto=proto)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid or unapproved origin URL: {e}")
    else:
        if host:
            origin_url = f"{proto}://{host}"
        else:
            origin_url = str(request.base_url).rstrip("/")

    client_ip = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or (request.client.host if request.client else None)
    target_user_id = req.user_id if (req and req.user_id and current_user.role == UserRole.ADMIN) else current_user.id
    return await auth_service.start_session(origin_url=origin_url, client_ip=client_ip, user_id=target_user_id)


@router.get("/api/auth/session/{session_id}", response_model=AuthSessionResponse)
async def get_auth_session(session_id: str):
    """Check the status of an ongoing authentication session."""
    session = await auth_service.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Authentication session not found")
    return session


@router.post("/api/auth/session/{session_id}/complete", response_model=AuthSessionResponse, dependencies=[Depends(rate_limit_dependency(10, 60, "auth_complete"))])
async def complete_auth_session(session_id: str, req: AuthCompleteRequest):
    """Receive authentication headers from companion extension or helper and validate them."""
    if not req.raw_headers.strip():
        raise HTTPException(status_code=400, detail="Headers cannot be empty")
    try:
        session = await auth_service.complete_session(session_id, req.raw_headers)
        return session
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to complete authentication: {e}")


@router.post("/api/auth/callback", response_model=AuthSessionResponse, dependencies=[Depends(rate_limit_dependency(10, 60, "auth_callback"))])
async def auth_callback_post(req: AuthCallbackRequest):
    """Callback endpoint for companion extensions/helpers submitting credentials."""
    if not req.raw_headers.strip():
        raise HTTPException(status_code=400, detail="Headers cannot be empty")
    try:
        session = await auth_service.complete_session(req.session_id, req.raw_headers)
        return session
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to complete authentication: {e}")


@router.get("/api/auth/callback", response_class=HTMLResponse)
async def auth_callback_get(session_id: Optional[str] = None):
    """Friendly browser landing page after authentication callback."""
    if not session_id:
        return HTMLResponse(
            content="""<!DOCTYPE html>
<html>
<head><title>Red Music Locker - Missing Session</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #121212; color: #fff; }
.card { background: #1e1e1e; padding: 2.5rem; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; max-width: 420px; }
h2 { color: #f44336; margin-top: 0; }
p { color: #aaa; line-height: 1.5; }
</style>
</head>
<body>
<div class="card">
  <h2>Invalid Request</h2>
  <p>Missing session parameter. Please return to Red Music Locker.</p>
</div>
</body>
</html>""",
            status_code=400
        )

    session = await auth_service.get_session(session_id)
    if not session or not session.connected:
        return HTMLResponse(
            content="""<!DOCTYPE html>
<html>
<head><title>Red Music Locker - Authentication Pending</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #121212; color: #fff; }
.card { background: #1e1e1e; padding: 2.5rem; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; max-width: 420px; }
h2 { color: #f44336; margin-top: 0; }
p { color: #aaa; line-height: 1.5; }
</style>
</head>
<body>
<div class="card">
  <h2>Authentication Pending or Incomplete</h2>
  <p>The authentication session has not completed or has expired. Please return to Red Music Locker and try again.</p>
</div>
</body>
</html>""",
            status_code=400
        )

    user_disp = session.user_name or "Connected Account"
    return HTMLResponse(
        content=f"""<!DOCTYPE html>
<html>
<head><title>Red Music Locker - Connected</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #121212; color: #fff; }}
.card {{ background: #1e1e1e; padding: 2.5rem; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; max-width: 420px; }}
h2 {{ color: #4caf50; margin-top: 0; }}
p {{ color: #ccc; line-height: 1.5; }}
.user {{ font-weight: bold; color: #fff; }}
</style>
</head>
<body>
<div class="card">
  <h2>✓ YouTube Music Connected</h2>
  <p>Successfully linked account: <span class="user">{user_disp}</span></p>
  <p>You can now safely close this window and return to Red Music Locker.</p>
</div>
</body>
</html>""",
        status_code=200
    )


@router.post("/api/auth/session/{session_id}/cancel", response_model=AuthSessionResponse)
async def cancel_auth_session(session_id: str):
    """Cancel an active authentication session."""
    session = await auth_service.cancel_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Authentication session not found")
    return session


@router.post("/api/auth/cancel", response_model=AuthSessionResponse)
async def cancel_auth_post(req: AuthCancelRequest):
    """Cancel an active authentication session via POST /api/auth/cancel."""
    session = await auth_service.cancel_session(req.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Authentication session not found")
    return session


@router.post("/api/auth/disconnect", response_model=ConnectionStatus)
async def disconnect_auth(current_user: User = Depends(require_authenticated_user)):
    """Safely disconnect YouTube Music account and remove stored credentials."""
    res = await auth_service.disconnect(user_id=current_user.id)
    return ConnectionStatus(
        connected=res["connected"],
        message=res["message"],
        user_name=res.get("user_name")
    )


@router.post("/api/auth/setup", response_model=ConnectionStatus)
async def setup_auth(req: AuthSetupRequest, current_user: User = Depends(require_authenticated_user)):
    """Direct/Developer setup: Parse raw headers and store credentials."""
    if not req.raw_headers.strip():
        raise HTTPException(status_code=400, detail="Headers cannot be empty")
    try:
        res = await ytm_client.setup_auth(req.raw_headers, user_id=current_user.id)
        if res.get("connected"):
            await db.create_or_update_ytm_account(
                user_id=current_user.id,
                account_name=res.get("user_name"),
                status="ACTIVE"
            )
        return ConnectionStatus(
            connected=res["connected"],
            message=res["message"],
            user_name=res.get("user_name")
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to setup authentication: {e}")


@router.post("/api/auth/test", response_model=ConnectionStatus)
async def test_auth(current_user: User = Depends(require_authenticated_user)):
    res = await ytm_client.test_connection(user_id=current_user.id)
    return ConnectionStatus(
        connected=res["connected"],
        message=res["message"],
        user_name=res.get("user_name")
    )


