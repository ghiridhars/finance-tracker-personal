"""
Local directory sync endpoints.

Provides endpoints to:
  - Check sync status & path configuration
  - Configure a local directory path
  - List statement files in the directory
  - Trigger a scan & import (background processing)
  - Poll scan progress
  - Reset sync state (allow re-processing)
"""
import logging
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from pydantic import BaseModel

from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/local-sync", tags=["Local Directory Sync"])


# ── Request/Response Models ────────────────────────────────────

class ConfigurePathRequest(BaseModel):
    path: str


class FileScanItem(BaseModel):
    filepath: str
    bank: str = "OTHER"
    type: str = "SAVINGS"


class ScanRequest(BaseModel):
    files: list[FileScanItem]
    force: bool = False


class ResetRequest(BaseModel):
    filepaths: list[str] | None = None


# ── Endpoints ──────────────────────────────────────────────────

@router.get("/status")
def local_sync_status():
    """
    Get local sync status and configuration.
    Returns the configured path, whether it exists, and last scan info.
    """
    from app.services.local_sync_service import get_sync_status
    return get_sync_status()


@router.post("/configure")
def local_sync_configure(body: ConfigurePathRequest):
    """
    Configure the local directory path for scanning.
    Validates the path exists and is a readable directory.
    Returns a count of matching statement files found.
    """
    try:
        from app.services.local_sync_service import configure_path
        return configure_path(body.path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/files")
def local_sync_list_files(
    path: Optional[str] = Query(
        None,
        description="Directory path to scan. Uses configured path if omitted.",
    ),
):
    """
    List statement files in the configured (or specified) local directory.
    Recursively scans for PDF, CSV, and Excel files.
    Shows inferred bank/type and whether each file has been processed.
    """
    try:
        from app.services.local_sync_service import list_local_files
        files = list_local_files(path=path)
        return {
            "file_count": len(files),
            "files": files,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to list local files: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to scan directory: {e}")


@router.post("/scan")
async def local_sync_scan(
    body: ScanRequest,
    background_tasks: BackgroundTasks,
):
    """
    Start scanning and importing selected files.

    Accepts a list of files with user-confirmed bank/type overrides.
    Processing runs in the background — poll /scan/{job_id} for progress.

    Returns immediately with a job_id.
    """
    if not body.files:
        raise HTTPException(status_code=400, detail="No files provided")

    from app.services.local_sync_service import (
        scan_and_import,
        create_job_id,
        has_running_scan,
    )

    if has_running_scan():
        raise HTTPException(
            status_code=409,
            detail="A scan is already in progress. Wait for it to complete before starting another.",
        )

    job_id = create_job_id()
    files_dicts = [f.model_dump() for f in body.files]

    async def _run_scan():
        # Create a fresh DB session for the background task — the request
        # session is closed by the time BackgroundTasks runs.
        db = SessionLocal()
        try:
            await scan_and_import(db=db, files=files_dicts, job_id=job_id, force=body.force)
        except Exception as e:
            logger.error(f"Local sync scan failed: {e}", exc_info=True)
        finally:
            db.close()

    background_tasks.add_task(_run_scan)

    return {
        "job_id": job_id,
        "total_files": len(body.files),
        "status": "started",
    }


@router.get("/scan/{job_id}")
def local_sync_scan_status(job_id: str):
    """
    Get the progress of a running or completed scan job.
    Returns per-file status and overall counts.
    """
    from app.services.local_sync_service import get_job_status

    status = get_job_status(job_id)
    if status is None:
        raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")

    return status


@router.post("/reset")
def local_sync_reset(body: ResetRequest):
    """
    Reset sync state so files can be re-processed.
    Pass specific filepaths to reset, or omit to reset all.
    """
    from app.services.local_sync_service import reset_sync_state
    return reset_sync_state(filepaths=body.filepaths)
