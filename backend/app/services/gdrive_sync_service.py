"""
Google Drive sync service.

Connects to a Google Drive folder (via service account) and downloads
new bank statement files, then feeds them through the existing parser pipeline.

Setup:
  1. Create a project in Google Cloud Console
  2. Enable the Google Drive API
  3. Create a service account and download the JSON key file
  4. Share your statements folder with the service account email
  5. Set GDRIVE_CREDENTIALS_FILE and GDRIVE_FOLDER_ID in .env
"""
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)

# Track processed files to avoid re-processing
_SYNC_STATE_FILE = Path(settings.data_dir) / ".gdrive_sync_state.json"


def _load_sync_state() -> dict:
    """Load the set of already-processed Drive file IDs."""
    if not _SYNC_STATE_FILE.exists():
        return {"processed_files": {}, "last_sync": None}
    try:
        return json.loads(_SYNC_STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, KeyError):
        return {"processed_files": {}, "last_sync": None}


def _save_sync_state(state: dict) -> None:
    """Persist sync state to disk."""
    _SYNC_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _SYNC_STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def _get_drive_service():
    """Build an authenticated Google Drive API service client."""
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    creds_path = settings.gdrive_credentials_file
    if not creds_path or not Path(creds_path).exists():
        raise ValueError(
            f"Google Drive credentials file not found: {creds_path}. "
            "Set GDRIVE_CREDENTIALS_FILE in .env"
        )

    credentials = service_account.Credentials.from_service_account_file(
        creds_path,
        scopes=["https://www.googleapis.com/auth/drive.readonly"],
    )
    return build("drive", "v3", credentials=credentials)


def _infer_file_type(filename: str) -> tuple[str, str]:
    """
    Infer bank and statement type from filename conventions.

    Delegates to the shared utility in app.utils.file_utils.
    Kept as a local wrapper for backward compatibility within this module.
    """
    from app.utils.file_utils import infer_file_type
    return infer_file_type(filename)


def get_sync_status() -> dict:
    """Return current sync configuration and state."""
    state = _load_sync_state()
    return {
        "enabled": settings.gdrive_enabled,
        "folder_id": settings.gdrive_folder_id or None,
        "credentials_configured": bool(
            settings.gdrive_credentials_file
            and Path(settings.gdrive_credentials_file).exists()
        ),
        "poll_interval_minutes": settings.gdrive_poll_interval_minutes,
        "last_sync": state.get("last_sync"),
        "processed_file_count": len(state.get("processed_files", {})),
    }


def list_drive_files() -> list[dict]:
    """List statement files in the configured Drive folder."""
    if not settings.gdrive_folder_id:
        raise ValueError("GDRIVE_FOLDER_ID not configured")

    service = _get_drive_service()

    # Query for PDF and CSV files in the target folder
    query = (
        f"'{settings.gdrive_folder_id}' in parents "
        "and trashed = false "
        "and (mimeType = 'application/pdf' "
        "or mimeType = 'text/csv' "
        "or mimeType = 'application/vnd.ms-excel' "
        "or mimeType = 'text/plain')"
    )

    results = (
        service.files()
        .list(
            q=query,
            fields="files(id, name, mimeType, size, modifiedTime, createdTime)",
            orderBy="modifiedTime desc",
            pageSize=100,
        )
        .execute()
    )

    state = _load_sync_state()
    processed = state.get("processed_files", {})

    files = []
    for f in results.get("files", []):
        files.append({
            "id": f["id"],
            "name": f["name"],
            "mimeType": f["mimeType"],
            "size": int(f.get("size", 0)),
            "modifiedTime": f.get("modifiedTime"),
            "createdTime": f.get("createdTime"),
            "already_processed": f["id"] in processed,
        })

    return files


async def sync_from_drive(
    db,
    bank_override: Optional[str] = None,
    type_override: Optional[str] = None,
    file_ids: Optional[list[str]] = None,
    force: bool = False,
) -> dict:
    """
    Download and parse new files from Google Drive.

    Args:
        db: SQLAlchemy session
        bank_override: Force all files to be parsed as this bank
        type_override: Force all files to be parsed as this statement type
        file_ids: Only sync specific file IDs (None = all new files)
        force: Re-process already-processed files

    Returns:
        Summary dict with counts of processed, skipped, failed files
    """
    from io import BytesIO
    from googleapiclient.http import MediaIoBaseDownload
    from app.models.enums import BankType, StatementType
    from app.services.parser_service import ParserService
    from app.parsers.csv_parser import parse_csv
    from app.services.credit_card_service import CreditCardStatementService
    from app.services.savings_service import SavingsAccountStatementService

    if not settings.gdrive_folder_id:
        raise ValueError("GDRIVE_FOLDER_ID not configured")

    service = _get_drive_service()
    parser_service = ParserService()

    state = _load_sync_state()
    processed = state.get("processed_files", {})

    # Get files from Drive
    all_files = list_drive_files()

    # Filter to requested files
    if file_ids:
        all_files = [f for f in all_files if f["id"] in file_ids]

    results = {
        "total": len(all_files),
        "processed": 0,
        "skipped": 0,
        "failed": 0,
        "details": [],
    }

    for file_info in all_files:
        file_id = file_info["id"]
        filename = file_info["name"]

        # Skip already processed (unless forced)
        if file_id in processed and not force:
            results["skipped"] += 1
            results["details"].append({
                "file": filename,
                "status": "skipped",
                "reason": "already processed",
            })
            continue

        try:
            # Download file content
            request = service.files().get_media(fileId=file_id)
            buffer = BytesIO()
            downloader = MediaIoBaseDownload(buffer, request)

            done = False
            while not done:
                _, done = downloader.next_chunk()

            content = buffer.getvalue()

            # Determine bank and statement type
            if bank_override:
                bank_str = bank_override
            else:
                bank_str, _ = _infer_file_type(filename)

            if type_override:
                type_str = type_override
            else:
                _, type_str = _infer_file_type(filename)

            bank_type = BankType.from_string(bank_str)
            statement_type = StatementType(type_str)

            # Parse based on file type
            is_csv = filename.lower().endswith((".csv", ".txt", ".tsv"))

            if is_csv:
                result = parse_csv(content, bank_type, statement_type)
                parser_used = "csv"
                success = result.success
                statement = result.result if success else None
                error = result.error_message if not success else None
            else:
                result = await parser_service.parse_statement(
                    content, filename, bank_type, statement_type
                )
                parser_used = result.get("parser", "unknown")
                success = result.get("success", False)
                statement = result.get("statement") if success else None
                error = result.get("error") if not success else None

            if success and statement:
                # Save to database
                if statement_type == StatementType.CREDIT_CARD:
                    CreditCardStatementService.save_statement(
                        db, statement, bank=bank_type.value
                    )
                else:
                    SavingsAccountStatementService.save_statement(
                        db, statement, bank=bank_type.value
                    )

                # Mark as processed
                processed[file_id] = {
                    "filename": filename,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "bank": bank_type.value,
                    "type": statement_type.value,
                    "parser": parser_used,
                }

                results["processed"] += 1
                results["details"].append({
                    "file": filename,
                    "status": "success",
                    "bank": bank_type.value,
                    "type": statement_type.value,
                    "parser": parser_used,
                })
            else:
                results["failed"] += 1
                results["details"].append({
                    "file": filename,
                    "status": "failed",
                    "error": error or "Parse returned no data",
                })

        except Exception as e:
            logger.error(f"Failed to process Drive file {filename}: {e}", exc_info=True)
            results["failed"] += 1
            results["details"].append({
                "file": filename,
                "status": "failed",
                "error": str(e),
            })

    # Update sync state
    state["processed_files"] = processed
    state["last_sync"] = datetime.now(timezone.utc).isoformat()
    _save_sync_state(state)

    results["last_sync"] = state["last_sync"]
    return results


def reset_sync_state(file_ids: Optional[list[str]] = None) -> dict:
    """
    Reset sync state so files can be re-processed.

    Args:
        file_ids: Specific file IDs to reset (None = reset all)
    """
    state = _load_sync_state()

    if file_ids:
        for fid in file_ids:
            state["processed_files"].pop(fid, None)
        removed = len(file_ids)
    else:
        removed = len(state["processed_files"])
        state["processed_files"] = {}

    _save_sync_state(state)
    return {"reset_count": removed}
