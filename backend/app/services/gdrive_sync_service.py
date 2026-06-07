"""
Google Drive sync service using personal OAuth2 authentication.

Connects to a user's personal Google Drive folder, lists files,
downloads selected statements, and imports them through the parser pipeline.
"""
import asyncio
import json
import logging
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from io import BytesIO

from app.config import settings
from app.parsing.diagnostics import annotate_parse_failure_message, extract_parse_failure
from app.utils.file_utils import infer_file_type, is_csv_file, review_status_from_parser, review_reason_from_result

logger = logging.getLogger(__name__)

# Token file for current authorized user
_TOKEN_FILE = Path(settings.data_dir) / ".gdrive_user_token.json"

# Folder → bank/type mapping config
_FOLDER_CONFIG_FILE = Path(settings.data_dir) / ".gdrive_folder_config.json"

# In-memory background job tracking
_gdrive_jobs: dict[str, dict] = {}
_jobs_lock = asyncio.Lock()


def _get_secrets_path() -> Path:
    """Find the credentials_google.json client secrets file."""
    p = Path(settings.gdrive_oauth_secrets_file)
    if p.exists():
        return p
    # Check parent workspace directory
    p_parent = Path("..") / settings.gdrive_oauth_secrets_file
    if p_parent.exists():
        return p_parent
    # Fallback absolute path
    p_abs = Path("/home/ghiridhars/Codebase/finance-tracker-personal/backend") / settings.gdrive_oauth_secrets_file
    if p_abs.exists():
        return p_abs
    raise ValueError(
        f"Google OAuth client secrets file '{settings.gdrive_oauth_secrets_file}' not found. "
        "Place your credentials_google.json at the backend workspace root."
    )


def _load_client_secrets() -> dict:
    """Load client secrets for the installed app OAuth flow."""
    path = _get_secrets_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        # Installed app credential JSON format typically nests everything under "installed"
        if "installed" in data:
            return data["installed"]
        elif "web" in data:
            return data["web"]
        return data
    except Exception as e:
        raise ValueError(f"Failed to read or parse client secrets file: {e}")


def get_auth_url(redirect_uri: str) -> str:
    """Generate the Google OAuth2 authorization URL."""
    secrets = _load_client_secrets()
    client_id = secrets["client_id"]
    
    # We require readonly drive access to list/download files, plus userinfo to get user email
    scopes = [
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/userinfo.email"
    ]
    scope_str = " ".join(scopes)
    
    import urllib.parse
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": scope_str,
        "access_type": "offline",  # Crucial to get refresh token
        "prompt": "consent"        # Force consent screen to guarantee refresh token is returned
    }
    return "https://accounts.google.com/o/oauth2/auth?" + urllib.parse.urlencode(params)


async def exchange_auth_code(code: str, redirect_uri: str) -> dict:
    """Exchange OAuth auth code for access + refresh tokens and save them."""
    secrets = _load_client_secrets()
    client_id = secrets["client_id"]
    client_secret = secrets["client_secret"]
    
    async with httpx.AsyncClient() as client:
        # Token exchange
        token_url = "https://oauth2.googleapis.com/token"
        data = {
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code"
        }
        
        token_res = await client.post(token_url, data=data)
        if token_res.status_code != 200:
            raise ValueError(f"Failed to exchange code: {token_res.text}")
        
        token_data = token_res.json()
        access_token = token_data["access_token"]
        refresh_token = token_data.get("refresh_token") # might be missing if prompt consent was omitted
        expires_in = token_data.get("expires_in", 3600)
        expires_at = time.time() + expires_in
        
        # Get user email
        userinfo_url = "https://www.googleapis.com/oauth2/v2/userinfo"
        headers = {"Authorization": f"Bearer {access_token}"}
        userinfo_res = await client.get(userinfo_url, headers=headers)
        
        email = None
        if userinfo_res.status_code == 200:
            email = userinfo_res.json().get("email")
            
        # If we already have a refresh token on disk, preserve it if not returned in this request
        existing_refresh_token = None
        if _TOKEN_FILE.exists():
            try:
                old_data = json.loads(_TOKEN_FILE.read_text(encoding="utf-8"))
                existing_refresh_token = old_data.get("refresh_token")
            except Exception:
                pass
                
        final_refresh_token = refresh_token or existing_refresh_token
        
        tokens_to_save = {
            "access_token": access_token,
            "refresh_token": final_refresh_token,
            "expires_at": expires_at,
            "email": email,
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        
        _TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        _TOKEN_FILE.write_text(json.dumps(tokens_to_save, indent=2), encoding="utf-8")
        
        return tokens_to_save


def get_connection_status() -> dict:
    """Return whether Google Drive is connected and user info."""
    if not _TOKEN_FILE.exists():
        return {"connected": False, "email": None}
    
    try:
        data = json.loads(_TOKEN_FILE.read_text(encoding="utf-8"))
        email = data.get("email")
        
        # Check if secrets file exists to confirm app config is healthy
        secrets_configured = False
        try:
            _get_secrets_path()
            secrets_configured = True
        except ValueError:
            pass
            
        return {
            "connected": True,
            "email": email,
            "secrets_configured": secrets_configured
        }
    except Exception:
        return {"connected": False, "email": None}


def disconnect() -> None:
    """Disconnect account by deleting stored user token on server."""
    if _TOKEN_FILE.exists():
        try:
            _TOKEN_FILE.unlink()
        except Exception as e:
            logger.error(f"Failed to delete Google user token file: {e}")


def _get_drive_service() -> build:
    """Build an authenticated Google Drive API client using saved tokens with auto-refresh."""
    if not _TOKEN_FILE.exists():
        raise ValueError("Google Drive is not connected. Authenticate first.")
        
    try:
        token_data = json.loads(_TOKEN_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        raise ValueError(f"Failed to read stored user tokens: {e}")
        
    secrets = _load_client_secrets()
    client_id = secrets["client_id"]
    client_secret = secrets["client_secret"]
    
    access_token = token_data["access_token"]
    refresh_token = token_data.get("refresh_token")
    expires_at = token_data.get("expires_at", 0)
    
    # Check if access token is expired and refresh it synchronously if possible
    if expires_at < time.time() + 60: # 60 seconds buffer
        if not refresh_token:
            raise ValueError("Google Drive access token expired and no refresh token found. Re-authenticate.")
            
        logger.info("Google Drive access token is expired. Refreshing...")
        try:
            token_url = "https://oauth2.googleapis.com/token"
            data = {
                "client_id": client_id,
                "client_secret": client_secret,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token"
            }
            res = httpx.post(token_url, data=data)
            if res.status_code != 200:
                raise ValueError(f"Failed to refresh access token: {res.text}")
                
            refresh_res = res.json()
            access_token = refresh_res["access_token"]
            expires_in = refresh_res.get("expires_in", 3600)
            expires_at = time.time() + expires_in
            
            # Update token file
            token_data["access_token"] = access_token
            token_data["expires_at"] = expires_at
            token_data["updated_at"] = datetime.now(timezone.utc).isoformat()
            _TOKEN_FILE.write_text(json.dumps(token_data, indent=2), encoding="utf-8")
            logger.info("Google Drive access token refreshed successfully.")
        except Exception as e:
            logger.error(f"Error refreshing Google access token: {e}")
            raise ValueError(f"Google authorization expired. Please log in again: {e}")
            
    creds = Credentials(
        token=access_token,
        refresh_token=refresh_token,
        token_uri="https://oauth2.googleapis.com/token",
        client_id=client_id,
        client_secret=client_secret
    )
    return build("drive", "v3", credentials=creds)


# ── Folder Configuration (bank/type mapping) ──────────────────

def get_folder_configs() -> dict:
    """Return all saved folder → bank/type mappings."""
    if not _FOLDER_CONFIG_FILE.exists():
        return {}
    try:
        return json.loads(_FOLDER_CONFIG_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}


def set_folder_config(folder_id: str, folder_name: str, bank: str, stmt_type: str, label: str = "") -> dict:
    """Save or update the bank/type mapping for a folder."""
    configs = get_folder_configs()
    configs[folder_id] = {
        "folder_id": folder_id,
        "folder_name": folder_name,
        "bank": bank,
        "type": stmt_type,
        "label": label or folder_name,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    _FOLDER_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    _FOLDER_CONFIG_FILE.write_text(json.dumps(configs, indent=2), encoding="utf-8")
    return configs[folder_id]


def delete_folder_config(folder_id: str) -> bool:
    """Remove the bank/type mapping for a folder. Returns True if it existed."""
    configs = get_folder_configs()
    if folder_id not in configs:
        return False
    del configs[folder_id]
    _FOLDER_CONFIG_FILE.write_text(json.dumps(configs, indent=2), encoding="utf-8")
    return True


def list_drive_folders(parent_id: str = "root") -> list[dict]:
    """List subfolders within a parent Google Drive folder."""
    service = _get_drive_service()
    
    query = f"'{parent_id}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    
    results = (
        service.files()
        .list(
            q=query,
            fields="files(id, name, modifiedTime, createdTime)",
            orderBy="name",
            pageSize=100,
        )
        .execute()
    )
    
    folders = []
    configs = get_folder_configs()
    for f in results.get("files", []):
        folder_id = f["id"]
        cfg = configs.get(folder_id)
        folders.append({
            "id": folder_id,
            "name": f["name"],
            "modifiedTime": f.get("modifiedTime"),
            "configured": cfg is not None,
            "config": cfg,
        })
        
    return folders


def list_drive_files(folder_id: str) -> list[dict]:
    """List supported statement files (PDF/CSV) inside a folder."""
    service = _get_drive_service()
    
    query = (
        f"'{folder_id}' in parents "
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
            orderBy="name",
            pageSize=100,
        )
        .execute()
    )
    
    # We will track processed files in our OAuth gdrive sync state separately
    state_file = Path(settings.data_dir) / ".gdrive_oauth_sync_state.json"
    processed = {}
    if state_file.exists():
        try:
            processed = json.loads(state_file.read_text(encoding="utf-8")).get("processed_files", {})
        except Exception:
            pass

    # Check if this folder has a saved bank/type mapping
    folder_config = get_folder_configs().get(folder_id)

    files = []
    for f in results.get("files", []):
        filename = f["name"]
        file_id = f["id"]
        
        # Prefer folder config over filename inference
        if folder_config:
            bank = folder_config["bank"]
            stmt_type = folder_config["type"]
        else:
            bank, stmt_type = infer_file_type(filename)
        
        files.append({
            "filepath": file_id, # for OAuth flow, filepath field is the file ID
            "relative_path": filename,
            "filename": filename,
            "size": int(f.get("size", 0)),
            "modified_time": f.get("modifiedTime"),
            "inferred_bank": bank,
            "inferred_type": stmt_type,
            "already_processed": file_id in processed,
            "file_key": file_id,
        })
        
    return files


async def download_and_import(
    db,
    files: list[dict],
    bank_passwords: Optional[dict[str, str]] = None,
    job_id: Optional[str] = None,
    force: bool = False,
) -> dict:
    """Background task that downloads selected files from Drive and parses them."""
    from app.models.enums import BankType, StatementType
    from app.parsing.service import ParserService
    from app.parsers.csv_parser import parse_csv
    from app.services.account_resolution_service import AccountResolutionService
    from app.services.statement_audit_service import StatementAuditService
    
    if not job_id:
        job_id = str(uuid.uuid4())[:8]
        
    service = _get_drive_service()
    parser_service = ParserService()
    
    # Load oauth gdrive sync state
    state_file = Path(settings.data_dir) / ".gdrive_oauth_sync_state.json"
    state = {"processed_files": {}}
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            pass
            
    processed = state.get("processed_files", {})
    
    results = {
        "job_id": job_id,
        "status": "running",
        "total": len(files),
        "processed": 0,
        "skipped": 0,
        "failed": 0,
        "current_file": None,
        "current_index": 0,
        "details": [],
    }
    
    async with _jobs_lock:
        _gdrive_jobs[job_id] = results
        
    for idx, file_info in enumerate(files):
        file_id = file_info["filepath"] # Drive file ID
        filename = file_info["filename"]
        bank_str = file_info.get("bank", "OTHER")
        type_str = file_info.get("type", "SAVINGS")
        
        results["current_file"] = filename
        results["current_index"] = idx + 1
        
        # Check skipped
        if file_id in processed and not force:
            results["skipped"] += 1
            results["details"].append({
                "filepath": file_id,
                "file": filename,
                "status": "skipped",
                "reason": "already processed",
            })
            continue
            
        try:
            # Download file from Drive API
            logger.info(f"GDrive OAuth Sync — Downloading '{filename}' ({file_id})")
            request = service.files().get_media(fileId=file_id)
            buffer = BytesIO()
            downloader = MediaIoBaseDownload(buffer, request)
            
            done = False
            while not done:
                _, done = downloader.next_chunk()
                
            content = buffer.getvalue()
            
            bank_type = BankType.from_string(bank_str)
            statement_type = StatementType(type_str)
            
            is_csv = is_csv_file(filename)
            
            if is_csv:
                result = parse_csv(content, bank_type, statement_type, filename=filename)
                parser_used = "csv"
                success = result.success
                statement = result.result if success else None
                error = result.error_message if not success else None
            else:
                pdf_password = (bank_passwords or {}).get(bank_str) or None
                result = await parser_service.parse_statement(
                    content, filename, bank_type, statement_type,
                    password=pdf_password
                )
                parser_used = result.get("parser", "unknown")
                success = result.get("success", False)
                statement = result.get("statement") if success else None
                error = result.get("error") if not success else None
                
            if success and statement:
                review_status = review_status_from_parser(
                    parser_used,
                    trusted=result.get("trusted") if isinstance(result, dict) else None,
                )
                review_reason = review_reason_from_result(result)
                
                # Resolve bank account
                if statement_type == StatementType.CREDIT_CARD:
                    acct_number = getattr(statement, "card_number", None)
                    holder = getattr(statement, "card_holder_name", None)
                else:
                    acct_number = getattr(statement, "account_number", None)
                    holder = getattr(statement, "account_holder_name", None)
                    
                bank_account = AccountResolutionService.resolve_or_create(
                    db,
                    bank_name=bank_type.value,
                    account_type=statement_type.value,
                    account_number=acct_number,
                    holder_name=holder
                )
                
                # Audit and persist statement
                strategy = result.get("strategy") if isinstance(result, dict) else "csv"
                StatementAuditService.save_statement(
                    db,
                    statement,
                    statement_type=statement_type,
                    bank_account_id=bank_account.id,
                    bank_name=bank_type.value,
                    file_name=filename,
                    file_content=content,
                    parser_strategy=strategy,
                    parse_trace=result.get("trace") if isinstance(result, dict) else None,
                    review_status=review_status,
                    review_reason=review_reason,
                    source="gdrive_oauth"
                )
                
                # Update processed set
                processed[file_id] = {
                    "filename": filename,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "bank": bank_type.value,
                    "type": statement_type.value,
                }
                
                results["processed"] += 1
                results["details"].append({
                    "filepath": file_id,
                    "file": filename,
                    "status": "success",
                    "bank": bank_type.value,
                    "type": statement_type.value,
                    "parser": parser_used,
                })
            else:
                parse_failure = extract_parse_failure(result if isinstance(result, dict) else None)
                error_message = annotate_parse_failure_message(
                    error or "Parse returned no data",
                    parse_failure,
                )
                StatementAuditService.record(
                    db,
                    file_name=filename,
                    file_content=content,
                    bank_name=bank_type.value,
                    statement_type=statement_type.value,
                    status="FAILED",
                    error_message=error_message,
                    parse_trace=result.get("trace") if isinstance(result, dict) else None,
                    source="gdrive_oauth",
                )
                db.commit()
                results["failed"] += 1
                detail = {
                    "filepath": file_id,
                    "file": filename,
                    "status": "failed",
                    "error": error_message,
                }
                if parse_failure is not None:
                    detail["parse_failure"] = parse_failure
                results["details"].append(detail)
                
        except Exception as e:
            if db:
                db.rollback()
            logger.error(f"Failed to download or parse Google Drive file '{filename}': {e}", exc_info=True)
            results["failed"] += 1
            results["details"].append({
                "filepath": file_id,
                "file": filename,
                "status": "failed",
                "error": str(e),
            })
            
        # Update state on disk
        try:
            state["processed_files"] = processed
            state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
        except Exception:
            pass
            
        await asyncio.sleep(0) # yield execution control
        
    results["status"] = "completed"
    results["current_file"] = None
    
    # Save final scan timestamp
    try:
        state["last_scan"] = datetime.now(timezone.utc).isoformat()
        state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    except Exception:
        pass
        
    return results


def get_job_status(job_id: str) -> Optional[dict]:
    """Retrieve progress status of an active or finished background import job."""
    return _gdrive_jobs.get(job_id)


def has_running_import() -> bool:
    """Check if any Google Drive import job is currently executing."""
    return any(job.get("status") in ("started", "running") for job in _gdrive_jobs.values())


def reset_gdrive_sync_state(file_ids: Optional[list[str]] = None) -> dict:
    """Reset processed cache so files can be re-imported."""
    state_file = Path(settings.data_dir) / ".gdrive_oauth_sync_state.json"
    state = {"processed_files": {}}
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            pass
            
    processed = state.get("processed_files", {})
    removed = 0
    
    if file_ids:
        for fid in file_ids:
            if fid in processed:
                del processed[fid]
                removed += 1
    else:
        removed = len(processed)
        processed = {}
        
    state["processed_files"] = processed
    state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return {"reset_count": removed}
