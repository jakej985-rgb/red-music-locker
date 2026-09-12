import asyncio
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from . import __version__
from .config import settings
from .database import db
from .models import User, UserRole
from .security import verify_api_key_header
from .scanner import scanner
from .ytm_client import ytm_client
from .auth_service import auth_service
from .matcher import matcher
from .uploader import queue_manager
from .playlist_watcher import playlist_watcher
from logging.handlers import RotatingFileHandler
from fastapi.staticfiles import StaticFiles

log_file = settings.log_file
logging.basicConfig(
    level=getattr(logging, settings.log_level, logging.INFO),
    format="%(asctime)s %(levelname)-5s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        RotatingFileHandler(log_file, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8")
    ]
)
logger = logging.getLogger("ytm_sync")

background_scanner_task: Optional[asyncio.Task] = None

async def _periodic_scan_loop():
    logger.info("Periodic background scanner initialized.")
    while True:
        try:
            interval_mins = await db.get_setting("scan_interval_minutes", default=settings.scan_interval_minutes)
            await asyncio.sleep(interval_mins * 60)
            
            folders = await db.get_setting("music_folders", default=[])
            if folders and not scanner.is_scanning:
                logger.info(f"Triggering scheduled periodic scan of {len(folders)} folders...")
                await scanner.scan_folders(folders)
                await matcher.match_all()

                auto_upload = await db.get_setting("auto_upload", default=False)
                if auto_upload and ytm_client.is_auth_configured():
                    logger.info("Auto-upload enabled: Enqueueing missing tracks...")
                    await queue_manager.enqueue_all_missing()
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Error in periodic background scan loop: {e}")
            await asyncio.sleep(30)

@asynccontextmanager
async def lifespan(app: FastAPI):
    global background_scanner_task
    # Startup: Initialize DB
    logger.info(f"Initializing database at {settings.db_path}...")
    await db.init_db()
    # Load persistent safety switch setting (Phase 13)
    saved_replacement_pref = await db.get_setting("allow_automatic_replacement", default=settings.allow_automatic_replacement)
    settings.allow_automatic_replacement = saved_replacement_pref
    # Recover interrupted upload jobs and resume worker if tasks are queued
    await queue_manager.reconcile_and_resume()
    # Start periodic background scanner
    background_scanner_task = asyncio.create_task(_periodic_scan_loop())
    # Start playlist watcher
    playlist_watcher.start()
    yield
    # Shutdown: Clean up background workers
    logger.info("Stopping background upload worker, periodic scanner, and playlist watcher...")
    playlist_watcher.stop()
    if background_scanner_task:
        background_scanner_task.cancel()
    await queue_manager.stop_worker()

app = FastAPI(
    title="Red Music Locker Backend Service",
    version=__version__,
    lifespan=lifespan,
    docs_url="/docs" if settings.enable_docs else None,
    redoc_url="/redoc" if settings.enable_docs else None,
    openapi_url="/openapi.json" if settings.enable_docs else None,
)

# CORS configuration allowing local network origins, companion extension, and YouTube Music
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^(https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|music\.youtube\.com)(:\d+)?|chrome-extension://.*)$",
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

@app.middleware("http")
async def authenticate_api_requests(request: Request, call_next):
    path = request.url.path
    # Allow public health endpoint, application login, and static frontend files
    if (
        path == "/health"
        or path == "/api/auth/login"
        or not path.startswith("/api/")
    ):
        return await call_next(request)
    # Allow CORS preflight OPTIONS requests without credentials
    if request.method == "OPTIONS":
        return await call_next(request)

    auth_hdr = request.headers.get("Authorization")

    # 1. Full access with master API key (maps to admin user)
    if verify_api_key_header(auth_hdr):
        users = await db.list_users()
        admin_user = next((u for u in users if u.role == UserRole.ADMIN), None)
        if admin_user:
            request.state.user = admin_user
        return await call_next(request)

    # 2. Check Scoped Temporary Extension Token (Phase C 4.2)
    bearer_token = None
    if auth_hdr and auth_hdr.strip().lower().startswith("bearer "):
        bearer_token = auth_hdr.strip().split(" ", 1)[1].strip()

    if bearer_token and auth_service.is_valid_extension_token(bearer_token):
        # Scoped extension tokens are strictly restricted to auth callback/completion
        if path == "/api/auth/callback" or (path.startswith("/api/auth/session/") and path.endswith("/complete")):
            return await call_next(request)
        else:
            return JSONResponse(
                status_code=403,
                content={"detail": "Extension token is restricted to authentication callback endpoints only."},
            )

    # 3. Check Active Application Session Token (Phase E & F)
    if bearer_token:
        user = await db.get_user_by_session_token(bearer_token)
        if user:
            request.state.user = user
            return await call_next(request)

    return JSONResponse(
        status_code=401,
        content={"detail": "Invalid or missing API key"},
        headers={"WWW-Authenticate": "Bearer"}
    )



# ============================================================================
# API Router Registration
# ============================================================================

from .routers.auth import router as auth_router
from .routers.users import router as users_router
from .routers.family import router as family_router
from .routers.settings_routes import router as settings_router
from .routers.ytm import router as ytm_router
from .routers.library import router as library_router
from .routers.sync import router as sync_router
from .routers.playlists import router as playlists_router
from .routers.recovery import router as recovery_router

app.include_router(auth_router)
app.include_router(users_router)
app.include_router(family_router)
app.include_router(settings_router)
app.include_router(ytm_router)
app.include_router(library_router)
app.include_router(sync_router)
app.include_router(playlists_router)
app.include_router(recovery_router)

class NoCacheStaticFiles(StaticFiles):
    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
        return response

# Mount Flutter Web frontend if built
web_dir_candidates = [
    settings.web_dir,
    Path(__file__).resolve().parent.parent / "web_dist",
    Path(__file__).resolve().parent.parent.parent / "app" / "build" / "web"
]
for candidate in web_dir_candidates:
    if candidate.is_dir() and (candidate / "index.html").exists():
        logger.info(f"Serving Flutter Web UI from {candidate}")
        app.mount("/", NoCacheStaticFiles(directory=str(candidate), html=True), name="web")
        break

def start():
    import uvicorn
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        proxy_headers=True,
        forwarded_allow_ips=settings.forwarded_allow_ips
    )

if __name__ == "__main__":
    start()
