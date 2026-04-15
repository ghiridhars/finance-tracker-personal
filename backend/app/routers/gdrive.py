"""
Google Drive sync endpoints.

Provides endpoints to:
  - Check sync status & configuration
  - List files in the connected Drive folder
  - Trigger a sync (download + parse new files)
  - Reset sync state (allow re-processing)
"""
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional

from app.database import get_db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/gdrive", tags=["Google Drive Sync"])


@router.get("/status")
def gdrive_status():
    """
    Get Google Drive sync status and configuration.
    Returns whether sync is enabled, configured, and last sync time.
    """
    from app.services.gdrive_sync_service import get_sync_status

    return get_sync_status()


@router.get("/files")
def gdrive_list_files():
    """
    List statement files found in the configured Google Drive folder.
    Shows which files have already been processed.
    """
    from app.config import settings

    if not settings.gdrive_enabled:
        raise HTTPException(status_code=400, detail="Google Drive sync is not enabled")

    try:
        from app.services.gdrive_sync_service import list_drive_files

        files = list_drive_files()
        return {
            "file_count": len(files),
            "files": files,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to list Drive files: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to connect to Google Drive: {e}")


@router.post("/sync")
async def gdrive_sync(
    bank: Optional[str] = Query(None, description="Override bank for all files"),
    type: Optional[str] = Query(None, description="Override statement type for all files"),
    file_ids: Optional[str] = Query(
        None,
        description="Comma-separated file IDs to sync (default: all new files)",
    ),
    force: bool = Query(False, description="Re-process already-processed files"),
    db: Session = Depends(get_db),
):
    """
    Sync files from Google Drive.

    Downloads new statement files from the configured folder,
    parses them, and saves transactions to the database.

    Uses the same parser pipeline as manual upload:
    regex parser → LLM fallback → CSV parser.
    """
    from app.config import settings

    if not settings.gdrive_enabled:
        raise HTTPException(status_code=400, detail="Google Drive sync is not enabled")

    try:
        from app.services.gdrive_sync_service import sync_from_drive

        parsed_file_ids = file_ids.split(",") if file_ids else None

        result = await sync_from_drive(
            db=db,
            bank_override=bank,
            type_override=type,
            file_ids=parsed_file_ids,
            force=force,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Drive sync failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Sync failed: {e}")


@router.post("/reset")
def gdrive_reset(
    file_ids: Optional[str] = Query(
        None,
        description="Comma-separated file IDs to reset (default: reset all)",
    ),
):
    """
    Reset sync state to allow re-processing of files.
    Useful when a file was updated or parsing was improved.
    """
    from app.config import settings

    if not settings.gdrive_enabled:
        raise HTTPException(status_code=400, detail="Google Drive sync is not enabled")

    from app.services.gdrive_sync_service import reset_sync_state

    parsed_ids = file_ids.split(",") if file_ids else None
    return reset_sync_state(file_ids=parsed_ids)
