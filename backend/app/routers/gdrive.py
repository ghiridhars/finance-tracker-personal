"""
Google Drive OAuth router.

Provides endpoints to:
  - Check user-auth connection status
  - Generate Google OAuth consent URL
  - Handle OAuth callback redirect (code exchange)
  - Revoke authentication / disconnect
  - Browse folders and files
  - Trigger background download and parse imports
  - Track import job progress
"""
import logging
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from app.database import SessionLocal
from app.auth import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/gdrive", tags=["Google Drive OAuth"])


# ── Request/Response DTOs ──────────────────────────────────────

class FileImportItem(BaseModel):
    filepath: str  # Represents Google Drive File ID
    filename: str
    bank: str = "OTHER"
    type: str = "SAVINGS"


class GDriveImportRequest(BaseModel):
    files: list[FileImportItem]
    force: bool = False
    bank_passwords: dict[str, str] = {}


class GDriveResetRequest(BaseModel):
    file_ids: list[str] | None = None


class FolderConfigRequest(BaseModel):
    folder_name: str
    bank: str
    type: str
    label: str = ""


# ── OAuth & Connection Endpoints ───────────────────────────────

@router.get("/status")
def gdrive_status(current_user: dict = Depends(get_current_user)):
    """Check if the user is connected to Google Drive."""
    from app.services.gdrive_sync_service import get_connection_status
    return get_connection_status()


@router.get("/auth-url")
def gdrive_auth_url(request: Request, current_user: dict = Depends(get_current_user)):
    """Generate the OAuth consent URL to initiate sign-in."""
    from app.services.gdrive_sync_service import get_auth_url
    
    try:
        # Build callback URI dynamically using current request's base URL
        redirect_uri = str(request.url_for("gdrive_callback"))
        auth_url = get_auth_url(redirect_uri)
        return {"auth_url": auth_url}
    except Exception as e:
        logger.error(f"Failed to generate Google auth URL: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to configure authentication: {e}")


@router.get("/callback", name="gdrive_callback")
async def gdrive_callback(code: str, request: Request, state: Optional[str] = None):
    """Google OAuth callback. Exchanges auth code for credentials."""
    from app.services.gdrive_sync_service import exchange_auth_code
    
    try:
        redirect_uri = str(request.url_for("gdrive_callback"))
        await exchange_auth_code(code, redirect_uri)
        
        # Render a beautiful, premium, modern success page matching the app's aesthetic!
        html_content = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Authentication Successful</title>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700&display=swap" rel="stylesheet">
            <style>
                body {
                    background-color: #0f172a;
                    color: #f8fafc;
                    font-family: 'Outfit', sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    overflow: hidden;
                }
                .card {
                    background: rgba(30, 41, 59, 0.7);
                    backdrop-filter: blur(16px);
                    border: 1px solid rgba(255, 255, 255, 0.08);
                    border-radius: 24px;
                    padding: 40px;
                    text-align: center;
                    max-width: 440px;
                    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
                    animation: scaleIn 0.5s cubic-bezier(0.16, 1, 0.3, 1);
                }
                .icon {
                    background: linear-gradient(135deg, #10b981, #059669);
                    width: 72px;
                    height: 72px;
                    border-radius: 50%;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    margin: 0 auto 24px auto;
                    box-shadow: 0 8px 16px rgba(16, 185, 129, 0.3);
                }
                .icon svg {
                    width: 36px;
                    height: 36px;
                    fill: none;
                    stroke: white;
                    stroke-width: 3;
                    stroke-linecap: round;
                    stroke-linejoin: round;
                }
                h1 {
                    font-size: 26px;
                    margin: 0 0 12px 0;
                    font-weight: 700;
                    letter-spacing: -0.5px;
                    background: linear-gradient(to right, #f8fafc, #cbd5e1);
                    -webkit-background-clip: text;
                    -webkit-text-fill-color: transparent;
                }
                p {
                    color: #94a3b8;
                    font-size: 15px;
                    line-height: 1.6;
                    margin: 0 0 28px 0;
                }
                .button {
                    background: linear-gradient(135deg, #3b82f6, #2563eb);
                    color: white;
                    text-decoration: none;
                    padding: 14px 28px;
                    border-radius: 12px;
                    font-weight: 600;
                    font-size: 14px;
                    display: inline-block;
                    box-shadow: 0 6px 12px rgba(37, 99, 235, 0.2);
                    transition: transform 0.2s, box-shadow 0.2s;
                }
                .button:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 8px 18px rgba(37, 99, 235, 0.3);
                }
                @keyframes scaleIn {
                    from { transform: scale(0.95); opacity: 0; }
                    to { transform: scale(1); opacity: 1; }
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="icon">
                    <svg viewBox="0 0 24 24">
                        <polyline points="20 6 9 17 4 12"></polyline>
                    </svg>
                </div>
                <h1>Sign In Successful</h1>
                <p>Finance Tracker is now authorized to browse your statements. You can safely close this browser window and head back to the app.</p>
                <a href="javascript:window.close()" class="button">Close Window</a>
            </div>
        </body>
        </html>
        """
        return HTMLResponse(content=html_content, status_code=200)
    except Exception as e:
        logger.error(f"Google OAuth callback code exchange failed: {e}", exc_info=True)
        # HTML error landing
        error_html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Authentication Failed</title>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700&display=swap" rel="stylesheet">
            <style>
                body {{ background-color: #0f172a; color: #f8fafc; font-family: 'Outfit', sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }}
                .card {{ background: rgba(30, 41, 59, 0.7); border: 1px solid rgba(239, 68, 68, 0.2); border-radius: 24px; padding: 40px; text-align: center; max-width: 440px; box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3); }}
                .icon {{ background: #ef4444; width: 72px; height: 72px; border-radius: 50%; display: flex; justify-content: center; align-items: center; margin: 0 auto 24px auto; }}
                h1 {{ font-size: 26px; margin: 0 0 12px 0; color: #fca5a5; }}
                p {{ color: #cbd5e1; font-size: 15px; line-height: 1.6; }}
            </style>
        </head>
        <body>
            <div class="card">
                <div class="icon">
                    <span style="font-size:36px;font-weight:bold;color:white;">!</span>
                </div>
                <h1>Authorization Failed</h1>
                <p>Failed to exchange Google OAuth authorization code: {e}</p>
            </div>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=400)


@router.post("/disconnect")
def gdrive_disconnect(current_user: dict = Depends(get_current_user)):
    """Log out / disconnect Google account on the server."""
    from app.services.gdrive_sync_service import disconnect
    disconnect()
    return {"success": True, "detail": "Disconnected successfully"}


# ── Directory Browsing Endpoints ───────────────────────────────

@router.get("/folders")
def gdrive_folders(
    parent_id: str = Query("root", description="Google Drive folder ID to browse"),
    current_user: dict = Depends(get_current_user)
):
    """List subfolders within a parent Google Drive directory."""
    from app.services.gdrive_sync_service import list_drive_folders
    
    try:
        folders = list_drive_folders(parent_id)
        return {
            "parent_id": parent_id,
            "folder_count": len(folders),
            "folders": folders
        }
    except Exception as e:
        logger.error(f"Failed to list Drive folders: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Google Drive Error: {e}")


@router.get("/files")
def gdrive_files(
    folder_id: str = Query(..., description="Google Drive folder ID to scan"),
    current_user: dict = Depends(get_current_user)
):
    """List supported bank statements (PDFs/CSVs) in the specified folder."""
    from app.services.gdrive_sync_service import list_drive_files
    
    try:
        files = list_drive_files(folder_id)
        return {
            "folder_id": folder_id,
            "file_count": len(files),
            "files": files
        }
    except Exception as e:
        logger.error(f"Failed to scan folder files: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Google Drive Error: {e}")


# ── Import & Progress Endpoints ────────────────────────────────

@router.post("/import")
async def gdrive_import(
    body: GDriveImportRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user)
):
    """
    Trigger background import for chosen statements.
    Downloads files from Google Drive and processes them asynchronously.
    """
    if not body.files:
        raise HTTPException(status_code=400, detail="No files specified for import")
        
    from app.services.gdrive_sync_service import (
        download_and_import,
        has_running_import,
        uuid
    )
    
    if has_running_import():
        raise HTTPException(
            status_code=409,
            detail="A Google Drive import job is already running. Please let it complete first."
        )
        
    job_id = str(uuid.uuid4())[:8]
    files_dicts = [f.model_dump() for f in body.files]
    
    async def _run_import():
        db = SessionLocal()
        try:
            await download_and_import(
                db=db,
                files=files_dicts,
                job_id=job_id,
                force=body.force,
                bank_passwords=body.bank_passwords
            )
        except Exception as e:
            logger.error(f"GDrive import failed for job {job_id}: {e}", exc_info=True)
        finally:
            db.close()
            
    background_tasks.add_task(_run_import)
    
    return {
        "job_id": job_id,
        "total_files": len(body.files),
        "status": "started"
    }


@router.get("/import/{job_id}")
def gdrive_import_status(job_id: str, current_user: dict = Depends(get_current_user)):
    """Poll progress status of an active or finished Google Drive import task."""
    from app.services.gdrive_sync_service import get_job_status
    
    status = get_job_status(job_id)
    if status is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
        
    return status


@router.post("/reset")
def gdrive_reset(body: GDriveResetRequest, current_user: dict = Depends(get_current_user)):
    """Reset processed file tracking cache on Google Drive."""
    from app.services.gdrive_sync_service import reset_gdrive_sync_state
    return reset_gdrive_sync_state(file_ids=body.file_ids)


# ── Folder Configuration Endpoints ─────────────────────────────

@router.get("/folder-configs")
def get_folder_configs(current_user: dict = Depends(get_current_user)):
    """Return all saved folder → bank/type mappings."""
    from app.services.gdrive_sync_service import get_folder_configs as _get
    return {"configs": list(_get().values())}


@router.post("/folder-configs/{folder_id}")
def save_folder_config(
    folder_id: str,
    body: FolderConfigRequest,
    current_user: dict = Depends(get_current_user),
):
    """Save or update the bank/type mapping for a specific folder."""
    from app.services.gdrive_sync_service import set_folder_config
    config = set_folder_config(
        folder_id=folder_id,
        folder_name=body.folder_name,
        bank=body.bank,
        stmt_type=body.type,
        label=body.label,
    )
    return config


@router.delete("/folder-configs/{folder_id}")
def remove_folder_config(folder_id: str, current_user: dict = Depends(get_current_user)):
    """Remove the bank/type mapping for a folder."""
    from app.services.gdrive_sync_service import delete_folder_config
    deleted = delete_folder_config(folder_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f"No config found for folder {folder_id}")
    return {"success": True, "folder_id": folder_id}
