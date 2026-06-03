"""
Local directory sync service.

Scans a configured local folder for bank statement files (PDF/CSV),
infers bank and statement type, and feeds them through the parser pipeline.

Mirrors the Google Drive sync service pattern but reads from the local filesystem.
"""
import asyncio
import hashlib
import json
import logging
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from app.config import settings
from app.parsers.base_parser import ParseException
from app.parsing.diagnostics import annotate_parse_failure_message, extract_parse_failure
from app.utils.file_utils import infer_file_type, is_csv_file, is_supported_file, review_status_from_parser

logger = logging.getLogger(__name__)

# Persistent state: which files have already been processed
_SYNC_STATE_FILE = Path(settings.data_dir) / ".local_sync_state.json"

# Path configuration persisted separately from env-based settings
_PATH_CONFIG_FILE = Path(settings.data_dir) / ".local_sync_config.json"

# In-memory job progress tracking (keyed by job_id)
_jobs: dict[str, dict] = {}

# Lock for state file access (defense-in-depth alongside single-scan enforcement)
_state_lock = asyncio.Lock()


def _normalize_password_candidates(
    password_value: str | list[str] | None,
) -> list[str]:
    """Return ordered, de-duplicated password candidates for a bank."""
    if password_value is None:
        return []

    raw_values = [password_value] if isinstance(password_value, str) else password_value
    candidates: list[str] = []
    seen: set[str] = set()

    for raw_value in raw_values:
        for part in re.split(r"[\r\n,]+", raw_value):
            candidate = part.strip()
            if candidate and candidate not in seen:
                candidates.append(candidate)
                seen.add(candidate)

    return candidates


def _is_incorrect_password_error(exc: Exception) -> bool:
    """Return True when the parser failed because the PDF password was wrong."""
    return str(exc).strip().lower() == "incorrect pdf password."


# ── Path Security ──────────────────────────────────────────────

def _get_allowed_roots() -> list[Path]:
    """
    Return the list of directories that are allowed as local sync roots.

    Priority:
      1. LOCAL_SYNC_ALLOWED_ROOTS env var (comma-separated absolute paths)
      2. Default: user home directory + data directory
    """
    if settings.local_sync_allowed_roots:
        return [Path(r.strip()).resolve() for r in settings.local_sync_allowed_roots.split(",") if r.strip()]

    roots = [Path(settings.data_dir).resolve()]
    home = Path.home()
    if home != Path("/"):
        roots.append(home)
    return roots


def _validate_path_allowed(path: Path) -> None:
    """
    Ensure a resolved path falls under one of the allowed root directories.
    Raises ValueError if the path is outside all allowed roots.
    """
    resolved = path.resolve()
    allowed = _get_allowed_roots()
    for root in allowed:
        try:
            resolved.relative_to(root)
            return
        except ValueError:
            continue

    allowed_str = ", ".join(str(r) for r in allowed)
    raise ValueError(
        f"Path '{resolved}' is outside allowed directories ({allowed_str}). "
        f"Set LOCAL_SYNC_ALLOWED_ROOTS to allow additional paths."
    )


# ── Path Configuration ─────────────────────────────────────────

def configure_path(path: str) -> dict:
    """
    Validate and persist a local directory path for scanning.

    Returns basic info about the configured path.
    """
    p = Path(path).resolve()

    if not p.exists():
        raise ValueError(f"Path does not exist: {path}")
    if not p.is_dir():
        raise ValueError(f"Path is not a directory: {path}")

    _validate_path_allowed(p)

    # Quick count of matching files
    file_count = sum(1 for f in p.rglob("*") if f.is_file() and is_supported_file(f.name))

    config = {
        "path": str(p),
        "configured_at": datetime.now(timezone.utc).isoformat(),
    }
    _PATH_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    _PATH_CONFIG_FILE.write_text(json.dumps(config, indent=2), encoding="utf-8")

    return {
        "success": True,
        "path": str(p),
        "file_count": file_count,
    }


def get_configured_path() -> str | None:
    """Read the currently configured local sync path."""
    # Prefer env-based setting, fall back to persisted config
    if settings.local_sync_path:
        return settings.local_sync_path

    if _PATH_CONFIG_FILE.exists():
        try:
            config = json.loads(_PATH_CONFIG_FILE.read_text(encoding="utf-8"))
            return config.get("path")
        except (json.JSONDecodeError, KeyError):
            pass

    return None


def get_sync_status() -> dict:
    """Return current configuration and sync state summary."""
    configured_path = get_configured_path()
    state = _load_sync_state()

    return {
        "configured_path": configured_path,
        "path_exists": bool(configured_path and Path(configured_path).is_dir()),
        "last_scan": state.get("last_scan"),
        "processed_file_count": len(state.get("processed_files", {})),
    }


# ── Sync State (processed files tracking) ──────────────────────

def _load_sync_state() -> dict:
    """Load the set of already-processed file hashes."""
    if not _SYNC_STATE_FILE.exists():
        return {"processed_files": {}, "last_scan": None}
    try:
        return json.loads(_SYNC_STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, KeyError):
        return {"processed_files": {}, "last_scan": None}


def _save_sync_state(state: dict) -> None:
    """Persist sync state to disk."""
    _SYNC_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _SYNC_STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def _file_key(filepath: Path) -> str:
    """
    Generate a stable key for a file based on its absolute path.
    Uses a hash of the path to avoid JSON key issues with special characters.
    """
    return hashlib.sha256(str(filepath.resolve()).encode()).hexdigest()[:16]


# ── File Discovery ─────────────────────────────────────────────

def list_local_files(path: str | None = None) -> list[dict]:
    """
    Recursively scan a directory for statement files.

    Returns a list of file metadata with inferred bank/type and processed status.
    Capped at settings.local_sync_max_files files, sorted by modification time (newest first).
    """
    scan_path = path or get_configured_path()
    if not scan_path:
        raise ValueError("No path configured. Call configure_path() first or set LOCAL_SYNC_PATH.")

    root = Path(scan_path).resolve()
    if not root.is_dir():
        raise ValueError(f"Path is not a directory: {scan_path}")

    _validate_path_allowed(root)

    state = _load_sync_state()
    processed = state.get("processed_files", {})

    files: list[dict] = []
    for f in root.rglob("*"):
        if not f.is_file() or not is_supported_file(f.name):
            continue

        try:
            stat = f.stat()
        except OSError:
            continue

        relative = str(f.relative_to(root))
        key = _file_key(f)
        bank, stmt_type = infer_file_type(f.name, relative)

        files.append({
            "filepath": str(f),
            "relative_path": relative,
            "filename": f.name,
            "size": stat.st_size,
            "modified_time": datetime.fromtimestamp(
                stat.st_mtime, tz=timezone.utc
            ).isoformat(),
            "inferred_bank": bank,
            "inferred_type": stmt_type,
            "already_processed": key in processed,
            "file_key": key,
        })

    # Sort by modification time (newest first) and cap
    files.sort(key=lambda x: x["modified_time"], reverse=True)
    return files[: settings.local_sync_max_files]


# ── Import / Scan ──────────────────────────────────────────────

async def scan_and_import(
    db,
    files: list[dict],
    job_id: str | None = None,
    force: bool = False,
    bank_passwords: dict[str, str | list[str]] | None = None,
) -> dict:
    """
    Parse and import a list of local files.

    Args:
        db: SQLAlchemy session
        files: List of dicts with {filepath, bank, type} — user-confirmed
        job_id: Job ID for progress tracking (auto-generated if None)
        force: Re-process already-processed files
        bank_passwords: Optional mapping of bank name -> one or more PDF passwords

    Returns:
        Summary dict with counts and per-file details.
    """
    from app.models.enums import BankType, StatementType
    from app.parsing.service import ParserService
    from app.parsers.csv_parser import parse_csv
    from app.services.account_resolution_service import AccountResolutionService
    from app.services.statement_audit_service import StatementAuditService

    if not job_id:
        job_id = str(uuid.uuid4())[:8]

    # Validate all submitted filepaths are within allowed directories
    configured = get_configured_path()
    scan_root = Path(configured).resolve() if configured else None
    for file_info in files:
        fp = Path(file_info["filepath"]).resolve()
        if scan_root:
            try:
                fp.relative_to(scan_root)
            except ValueError:
                raise ValueError(
                    f"File path '{fp}' is outside the configured directory '{scan_root}'"
                )
        _validate_path_allowed(fp)

    parser_service = ParserService()
    state = _load_sync_state()
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
    _jobs[job_id] = results

    for idx, file_info in enumerate(files):
        filepath = Path(file_info["filepath"])
        filename = filepath.name
        bank_str = file_info.get("bank", "OTHER")
        type_str = file_info.get("type", "SAVINGS")

        results["current_file"] = filename
        results["current_index"] = idx + 1

        key = _file_key(filepath)

        # Skip already processed (unless forced)
        if key in processed and not force:
            results["skipped"] += 1
            results["details"].append({
                "file": filename,
                "filepath": str(filepath),
                "status": "skipped",
                "reason": "already processed",
            })
            continue

        # Check file still exists
        if not filepath.is_file():
            results["failed"] += 1
            results["details"].append({
                "file": filename,
                "filepath": str(filepath),
                "status": "failed",
                "error": "File not found (may have been moved or deleted)",
            })
            continue

        # Check file size
        try:
            file_size = filepath.stat().st_size
            if file_size > settings.max_upload_size_bytes:
                results["failed"] += 1
                results["details"].append({
                    "file": filename,
                    "filepath": str(filepath),
                    "status": "failed",
                    "error": f"File too large ({file_size} bytes). Max: {settings.max_upload_size_mb}MB",
                })
                continue
        except OSError as e:
            results["failed"] += 1
            results["details"].append({
                "file": filename,
                "filepath": str(filepath),
                "status": "failed",
                "error": f"Cannot read file: {e}",
            })
            continue

        try:
            content = filepath.read_bytes()
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
                password_candidates = _normalize_password_candidates(
                    (bank_passwords or {}).get(bank_str)
                )

                if password_candidates:
                    result = None
                    last_password_error: Exception | None = None

                    for candidate in password_candidates:
                        try:
                            result = await parser_service.parse_statement(
                                content,
                                filename,
                                bank_type,
                                statement_type,
                                password=candidate,
                            )
                            last_password_error = None
                            break
                        except Exception as e:
                            if _is_incorrect_password_error(e):
                                last_password_error = e
                                continue
                            raise

                    if result is None:
                        raise last_password_error or ParseException(
                            "Incorrect PDF password."
                        )
                else:
                    result = await parser_service.parse_statement(
                        content,
                        filename,
                        bank_type,
                        statement_type,
                        password=None,
                    )

                parser_used = result.get("parser", "unknown")
                success = result.get("success", False)
                statement = result.get("statement") if success else None
                error = result.get("error") if not success else None

            if success and statement:
                # Determine review_status from parser used
                review_status = review_status_from_parser(
                    parser_used,
                    trusted=result.get("trusted") if isinstance(result, dict) else None,
                )

                # Resolve or create bank account
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
                    holder_name=holder,
                )

                # Save via unified audit service
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
                    source="local_sync",
                )

                # Mark as processed
                processed[key] = {
                    "filepath": str(filepath),
                    "filename": filename,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "bank": bank_type.value,
                    "type": statement_type.value,
                    "parser": parser_used,
                }

                results["processed"] += 1
                results["details"].append({
                    "file": filename,
                    "filepath": str(filepath),
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
                # Record failed audit
                StatementAuditService.record(
                    db,
                    file_name=filename,
                    file_content=content,
                    bank_name=bank_type.value,
                    statement_type=statement_type.value,
                    status="FAILED",
                    error_message=error_message,
                    parse_trace=result.get("trace") if isinstance(result, dict) else None,
                    source="local_sync",
                )
                db.commit()
                results["failed"] += 1
                detail = {
                    "file": filename,
                    "filepath": str(filepath),
                    "status": "failed",
                    "error": error_message,
                }
                if parse_failure is not None:
                    detail["parse_failure"] = parse_failure
                results["details"].append(detail)

        except Exception as e:
            db.rollback()
            logger.error(f"Failed to process local file {filename}: {e}", exc_info=True)
            results["failed"] += 1
            results["details"].append({
                "file": filename,
                "filepath": str(filepath),
                "status": "failed",
                "error": str(e),
            })

        # Persist state after each file so progress survives crashes
        async with _state_lock:
            state["processed_files"] = processed
            _save_sync_state(state)

        # Yield control to event loop between files
        await asyncio.sleep(0)

    # Final state update
    async with _state_lock:
        state["processed_files"] = processed
        state["last_scan"] = datetime.now(timezone.utc).isoformat()
        _save_sync_state(state)

    results["status"] = "completed"
    results["current_file"] = None
    results["last_scan"] = state["last_scan"]

    return results


# ── Job Status ─────────────────────────────────────────────────

def has_running_scan() -> bool:
    """Check if any scan job is currently running."""
    return any(j.get("status") == "running" for j in _jobs.values())


def get_job_status(job_id: str) -> dict | None:
    """Return current progress of a running or completed job."""
    return _jobs.get(job_id)


def create_job_id() -> str:
    """Generate a new job ID."""
    return str(uuid.uuid4())[:8]


# ── Reset ──────────────────────────────────────────────────────

def reset_sync_state(filepaths: Optional[list[str]] = None) -> dict:
    """
    Reset sync state so files can be re-processed.

    Args:
        filepaths: Specific file paths to reset (None = reset all)
    """
    state = _load_sync_state()

    if filepaths:
        keys_to_remove = {_file_key(Path(fp)) for fp in filepaths}
        removed = 0
        for key in keys_to_remove:
            if key in state["processed_files"]:
                del state["processed_files"][key]
                removed += 1
    else:
        removed = len(state["processed_files"])
        state["processed_files"] = {}

    _save_sync_state(state)
    return {"reset_count": removed}
