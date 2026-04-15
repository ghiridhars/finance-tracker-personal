"""
Unified statement upload endpoint.
Supports any bank/statement type via the parser registry.

New endpoints:
  POST /api/v2/statements/upload       — PDF upload (any bank)
  POST /api/v2/statements/upload-csv   — CSV/Excel upload (any bank)
  GET  /api/v2/banks                   — list supported banks
"""
import logging

from fastapi import APIRouter, UploadFile, File, HTTPException, Query, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.enums import BankType, StatementType
from app.parsers.parser_registry import get_registered_banks
from app.services.parser_service import ParserService
from app.services.credit_card_service import CreditCardStatementService
from app.services.savings_service import SavingsAccountStatementService

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
            content, file.filename or "upload.pdf", bank_type, statement_type
        )

        if not result.get("success"):
            error_detail = result.get("error", "Failed to parse statement")
            logger.warning(f"Statement parse failed [{bank_type.value}/{statement_type.value}]: {error_detail}")
            raise HTTPException(
                status_code=400,
                detail=error_detail,
            )

        statement = result.get("statement")
        if statement is None:
            raise HTTPException(status_code=400, detail="Parser returned no data")

        # Save to DB if requested
        if save:
            # Determine review_status from parser used
            parser_used = result.get("parser", "unknown")
            if "llm" in parser_used.lower():
                review_status = "LLM_PARSED"
            else:
                review_status = "AUTO_PARSED"
            statement = _save_statement(db, statement, statement_type, bank=bank_type.value, review_status=review_status)

        return {
            "success": True,
            "bank": bank_type.value,
            "statement_type": statement_type.value,
            "parser_used": result.get("parser", "unknown"),
            "statement": _serialize_statement(statement),
        }

    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error(f"Error processing statement: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing statement: {e}")


def _save_statement(db: Session, statement, statement_type: StatementType, bank: str | None = None, review_status: str | None = None):
    """Save parsed statement to the appropriate table."""
    if statement_type == StatementType.CREDIT_CARD:
        return CreditCardStatementService.save_statement(db, statement, bank=bank, review_status=review_status)
    elif statement_type == StatementType.SAVINGS:
        return SavingsAccountStatementService.save_statement(db, statement, bank=bank, review_status=review_status)
    else:
        raise ValueError(f"Cannot save statement type: {statement_type.value}")


def _serialize_statement(statement) -> dict:
    """Convert statement (Pydantic schema or SQLAlchemy model) to a dict."""
    if hasattr(statement, "model_dump"):
        # Pydantic model
        return statement.model_dump(mode="json")
    elif hasattr(statement, "__dict__"):
        # SQLAlchemy model — use schema validation
        from app.schemas.credit_card import CreditCardStatementSchema
        from app.schemas.savings_account import SavingsAccountStatementSchema

        try:
            return CreditCardStatementSchema.model_validate(statement).model_dump(mode="json")
        except Exception:
            pass
        try:
            return SavingsAccountStatementSchema.model_validate(statement).model_dump(mode="json")
        except Exception:
            pass

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

        # Save to DB if requested
        if save:
            statement = _save_statement(db, statement, statement_type, bank=bank_type.value)

        return {
            "success": True,
            "bank": bank_type.value,
            "statement_type": statement_type.value,
            "parser_used": "csv",
            "statement": _serialize_statement(statement),
        }

    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error(f"Error processing CSV: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing CSV: {e}")
