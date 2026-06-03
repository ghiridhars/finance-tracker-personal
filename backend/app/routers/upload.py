"""
Unified statement upload endpoint.
Supports any bank/statement type via the parser registry.

New endpoints:
  POST /api/v2/statements/upload       — PDF upload (any bank)
  POST /api/v2/statements/upload-csv   — CSV/Excel upload (any bank)
  GET  /api/v2/banks                   — list supported banks
"""
import logging

from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Query, Depends
from fastapi.responses import JSONResponse
from typing import Optional
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.enums import BankType, StatementType
from app.parsing.service import ParserService
from app.parsing.diagnostics import annotate_parse_failure_message, extract_parse_failure
from app.parsers.parser_registry import get_registered_banks
from app.services.account_resolution_service import AccountResolutionService
from app.services.statement_audit_service import StatementAuditService
from app.utils.file_utils import review_status_from_parser

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2", tags=["Upload (v2)"])

parser_service = ParserService()


@router.get("/banks")
def list_supported_banks():
    """
    List all supported bank/statement_type combinations.
    Useful for frontend dropdown population.
    """
    registered = get_registered_banks()

    # Also report that LLM fallback covers any bank
    from app.config import settings
    llm_enabled = settings.llm_provider.lower() != "none"

    return {
        "registered_parsers": registered,
        "llm_enabled": llm_enabled,
        "llm_provider": settings.llm_provider if llm_enabled else None,
        "llm_model": (
            settings.ollama_model
            if settings.llm_provider.lower() == "ollama"
            else settings.gemini_model
            if settings.llm_provider.lower() == "gemini"
            else None
        ),
        "supported_banks": [b.value for b in BankType],
        "supported_statement_types": [s.value for s in StatementType],
        "note": "Generic PDF parser runs first for speed and accuracy. "
                "LLM fallback handles non-tabular formats."
                if llm_enabled
                else "LLM is disabled. Using generic PDF parser only. "
                     "Set LLM_PROVIDER=ollama for fallback on unusual formats.",
    }


@router.post("/statements/upload")
async def upload_statement_v2(
    file: UploadFile = File(...),
    bank: str = Query(..., description="Bank name (e.g., HDFC, BOB, FEDERAL_BANK)"),
    type: str = Query(
        ...,
        alias="type",
        description="Statement type: SAVINGS or CREDIT_CARD",
    ),
    save: bool = Query(True, description="Whether to save to database"),
    password: Optional[str] = Form(None, description="Password for encrypted PDFs"),
    db: Session = Depends(get_db),
):
    """
    Unified statement upload endpoint.

    Accepts any bank + statement type combination.
    Generic PDF parser runs first for speed. LLM fallback (if enabled)
    handles non-tabular or unusual statement formats.

    Query params:
      - bank: HDFC, ICICI, SBI, AXIS, KOTAK, YES_BANK, BOB, FEDERAL_BANK, OTHER
      - type: SAVINGS, CREDIT_CARD
      - save: true/false (default: true)
    """
    # Resolve bank and statement type enums
    try:
        bank_type = BankType.from_string(bank)
    except Exception:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown bank: {bank}. Supported: {[b.value for b in BankType]}",
        )

    try:
        statement_type = StatementType(type.upper())
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown statement type: {type}. "
                   f"Supported: {[s.value for s in StatementType if s != StatementType.CSV]}",
        )

    # Content-type validation
    if file.content_type not in ("application/pdf", "application/octet-stream"):
        raise HTTPException(status_code=415, detail="Unsupported media type: expected PDF")

    try:
        content = await file.read()

        # Server-side file size check
        from app.config import settings as app_settings
        if len(content) > app_settings.max_upload_size_bytes:
            raise HTTPException(
                status_code=400,
                detail=f"File too large. Max: {app_settings.max_upload_size_mb}MB",
            )

        # Magic bytes validation: PDF files start with %PDF
        if not content[:5].startswith(b"%PDF-"):
            raise HTTPException(
                status_code=415,
                detail="File content is not a valid PDF",
            )

        result = await parser_service.parse_statement(
            content,
            file.filename or "upload.pdf",
            bank_type,
            statement_type,
            password=password or None,
        )

        if not result.get("success"):
            parse_failure = extract_parse_failure(result if isinstance(result, dict) else None)
            error_detail = annotate_parse_failure_message(
                result.get("error", "Failed to parse statement"),
                parse_failure,
            )
            logger.warning(f"Statement parse failed [{bank_type.value}/{statement_type.value}]: {error_detail}")
            # Record failed audit
            StatementAuditService.record(
                db,
                file_name=file.filename or "upload.pdf",
                file_content=content,
                bank_name=bank_type.value,
                statement_type=statement_type.value,
                status="FAILED",
                error_message=error_detail,
                parse_trace=result.get("trace") if isinstance(result, dict) else None,
                source="upload",
            )
            db.commit()
            if parse_failure is not None:
                return JSONResponse(
                    status_code=400,
                    content={
                        "detail": error_detail,
                        "parse_failure": parse_failure,
                    },
                )
            raise HTTPException(status_code=400, detail=error_detail)

        statement = result.get("statement")
        if statement is None:
            raise HTTPException(status_code=400, detail="Parser returned no data")

        # Save to DB if requested
        if save:
            # Determine review_status from parser used
            parser_used = result.get("parser", "unknown")
            review_status = review_status_from_parser(
                parser_used,
                trusted=result.get("trusted"),
            )

            # Resolve or create bank account
            account_number = _get_account_number(statement, statement_type)
            holder_name = _get_holder_name(statement, statement_type)
            bank_account = AccountResolutionService.resolve_or_create(
                db,
                bank_name=bank_type.value,
                account_type=statement_type.value,
                account_number=account_number,
                holder_name=holder_name,
            )

            audit = StatementAuditService.save_statement(
                db,
                statement,
                statement_type=statement_type,
                bank_account_id=bank_account.id,
                bank_name=bank_type.value,
                file_name=file.filename or "upload.pdf",
                file_content=content,
                parser_strategy=result.get("strategy"),
                parse_trace=result.get("trace") if isinstance(result, dict) else None,
                review_status=review_status,
                source="upload",
            )

        return {
            "success": True,
            "bank": bank_type.value,
            "statement_type": statement_type.value,
            "parser_used": result.get("parser", "unknown"),
            "statement": _serialize_statement(statement),
            "audit_id": audit.id if save else None,
        }

    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error(f"Error processing statement: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing statement: {e}")


def _get_account_number(statement, statement_type: StatementType) -> str | None:
    """Extract the account/card number from a parsed statement schema."""
    if statement_type == StatementType.CREDIT_CARD:
        return getattr(statement, "card_number", None)
    return getattr(statement, "account_number", None)


def _get_holder_name(statement, statement_type: StatementType) -> str | None:
    """Extract the holder name from a parsed statement schema."""
    if statement_type == StatementType.CREDIT_CARD:
        return getattr(statement, "card_holder_name", None)
    return getattr(statement, "account_holder_name", None)


def _serialize_statement(statement) -> dict:
    """Convert a Pydantic DTO to a dict for the response."""
    if hasattr(statement, "model_dump"):
        return statement.model_dump(mode="json")
    # Fallback
    return {"raw": str(statement)}


@router.post("/statements/upload-csv")
async def upload_csv_statement(
    file: UploadFile = File(...),
    bank: str = Query(..., description="Bank name (e.g., HDFC, BOB, FEDERAL_BANK)"),
    type: str = Query(
        ...,
        alias="type",
        description="Statement type: SAVINGS or CREDIT_CARD",
    ),
    save: bool = Query(True, description="Whether to save to database"),
    db: Session = Depends(get_db),
):
    """
    Upload a CSV/Excel bank statement.

    Auto-detects column mappings (Date, Description, Debit, Credit, Balance, etc.)
    Works for any bank's CSV or Excel download.

    Supported file types: .csv, .txt (tab-separated), .xlsx, .xls
    """
    # Validate bank and type
    try:
        bank_type = BankType.from_string(bank)
    except Exception:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown bank: {bank}. Supported: {[b.value for b in BankType]}",
        )

    try:
        statement_type = StatementType(type.upper())
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown statement type: {type}. "
                   f"Supported: SAVINGS, CREDIT_CARD",
        )

    # Validate file type
    filename = file.filename or "upload.csv"
    allowed_extensions = (".csv", ".txt", ".tsv", ".xlsx", ".xls")
    if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type. Expected: {', '.join(allowed_extensions)}",
        )

    try:
        content = await file.read()

        # Size check
        max_size = 10 * 1024 * 1024  # 10MB
        if len(content) > max_size:
            raise HTTPException(status_code=400, detail="File too large. Max: 10MB")

        from app.parsers.csv_parser import parse_csv

        result = parse_csv(content, bank_type, statement_type, filename=filename)

        if not result.success:
            raise HTTPException(
                status_code=400,
                detail=result.error_message or "Failed to parse CSV",
            )

        statement = result.result
        if statement is None:
            raise HTTPException(status_code=400, detail="CSV parser returned no data")

        audit = None
        # Save to DB if requested
        if save:
            account_number = _get_account_number(statement, statement_type)
            holder_name = _get_holder_name(statement, statement_type)
            bank_account = AccountResolutionService.resolve_or_create(
                db,
                bank_name=bank_type.value,
                account_type=statement_type.value,
                account_number=account_number,
                holder_name=holder_name,
            )

            audit = StatementAuditService.save_statement(
                db,
                statement,
                statement_type=statement_type,
                bank_account_id=bank_account.id,
                bank_name=bank_type.value,
                file_name=filename,
                file_content=content,
                parser_strategy="csv",
                review_status="AUTO_PARSED",
                source="upload",
            )

        return {
            "success": True,
            "bank": bank_type.value,
            "statement_type": statement_type.value,
            "parser_used": "csv",
            "statement": _serialize_statement(statement),
            "audit_id": audit.id if audit else None,
        }

    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error(f"Error processing CSV: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing CSV: {e}")
