"""
Accounts & Statement Management router.

Endpoints:
  - GET  /api/v2/accounts                    — List linked accounts/cards
  - PATCH /api/v2/accounts/rename            — Rename an account
  - GET  /api/v2/accounts/statements         — List statements (unified, paginated)
  - DELETE /api/v2/accounts/statements/{id}  — Delete a statement + its transactions
  - DELETE /api/v2/transactions/{id}         — Delete unified transaction
"""
import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.parsing.diagnostics import extract_parse_failure
from app.services.accounts_service import AccountsService, StatementManagementService

router = APIRouter(prefix="/api/v2/accounts", tags=["Accounts & Statements"])


@router.get("")
def list_accounts(db: Session = Depends(get_db)):
    """
    List all known accounts and credit cards,
    with statement count, transaction count, and latest balance.
    """
    return AccountsService.get_accounts(db)


@router.patch("/rename")
def rename_account(
    account_type: str = Query(..., description="SAVINGS or CREDIT_CARD"),
    identifier: str = Query(..., description="Account number or card number"),
    name: str = Query(..., description="New display name for the account"),
    db: Session = Depends(get_db),
):
    """Rename an account (update holder name on bank_accounts)."""
    if account_type not in ("SAVINGS", "CREDIT_CARD"):
        raise HTTPException(status_code=400, detail="account_type must be SAVINGS or CREDIT_CARD")
    updated = AccountsService.rename_account(db, account_type, identifier, name)
    if not updated:
        raise HTTPException(status_code=404, detail="Account not found")
    return {"detail": "Account renamed", "identifier": identifier, "name": name}


@router.get("/statements")
def list_statements(
    statement_type: Optional[str] = Query(None, description="SAVINGS or CREDIT_CARD"),
    bank_account_id: Optional[int] = Query(None),
    status: Optional[str] = Query(None, description="SUCCESS or FAILED"),
    include_trace: bool = Query(False, description="Include stored parse trace for debug use"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """List successful statement imports (paginated). Optionally filter by type or account."""
    if status is not None and status not in {"SUCCESS", "FAILED"}:
        raise HTTPException(status_code=400, detail="status must be SUCCESS or FAILED")

    items, total = StatementManagementService.list_statements(
        db, statement_type=statement_type, bank_account_id=bank_account_id, status=status,
        limit=limit, offset=offset,
    )
    return {
        "items": [_audit_to_dict(s, include_trace=include_trace) for s in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.delete("/statements/{audit_id}")
def delete_statement(audit_id: int, db: Session = Depends(get_db)):
    """Delete a statement and all its associated unified transactions."""
    deleted = StatementManagementService.delete_statement(db, audit_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Statement not found")
    return {"detail": "Statement deleted", "id": audit_id}


def _audit_to_dict(audit, *, include_trace: bool = False) -> dict:
    """Serialize a StatementAudit row for the API response."""
    trace_payload = _deserialize_trace(audit.parse_trace) if audit.parse_trace else None
    validation = _extract_validation(trace_payload)
    parse_failure = _extract_parse_failure(trace_payload, audit)
    payload = {
        "id": audit.id,
        "file_name": audit.file_name,
        "bank_name": audit.bank_name,
        "statement_type": audit.statement_type,
        "bank_account_id": audit.bank_account_id,
        "period_start": audit.period_start.isoformat() if audit.period_start else None,
        "period_end": audit.period_end.isoformat() if audit.period_end else None,
        "opening_balance": float(audit.opening_balance) if audit.opening_balance else None,
        "closing_balance": float(audit.closing_balance) if audit.closing_balance else None,
        "due_date": audit.due_date.isoformat() if audit.due_date else None,
        "credit_limit": float(audit.credit_limit) if audit.credit_limit else None,
        "available_credit": float(audit.available_credit) if audit.available_credit else None,
        "minimum_amount_due": float(audit.minimum_amount_due) if audit.minimum_amount_due else None,
        "transaction_count": audit.transaction_count,
        "parser_strategy": audit.parser_strategy,
        "source": audit.source,
        "imported_at": audit.imported_at.isoformat() if audit.imported_at else None,
    }
    audit_status = getattr(audit, "status", None)
    if audit_status is not None:
        payload["status"] = audit_status
    error_message = getattr(audit, "error_message", None)
    if error_message:
        payload["error_message"] = error_message
    if parse_failure is not None:
        payload["parse_failure"] = parse_failure
    if validation is not None:
        payload["trusted"] = validation.get("trusted")
        payload["validation_failed_codes"] = _failed_validation_codes(validation)
        payload["validation_summary"] = _validation_summary(validation)
    if include_trace and trace_payload is not None:
        payload["parse_trace"] = trace_payload
    return payload


def _deserialize_trace(raw_trace: str):
    try:
        return json.loads(raw_trace)
    except json.JSONDecodeError:
        return raw_trace


def _extract_validation(trace_payload):
    if not isinstance(trace_payload, dict):
        return None
    validation = trace_payload.get("validation")
    if isinstance(validation, dict):
        return validation
    return None


def _extract_parse_failure(trace_payload, audit) -> dict | None:
    return extract_parse_failure(
        {
            "trace": trace_payload,
            "error": getattr(audit, "error_message", None),
            "parser": getattr(audit, "parser_strategy", None),
        }
    )


def _failed_validation_codes(validation: dict) -> list[str]:
    failed_codes: list[str] = []
    for check in validation.get("checks", []):
        if check.get("status") == "failed" and check.get("code"):
            failed_codes.append(check["code"])
    return failed_codes


def _validation_summary(validation: dict) -> dict:
    summary = validation.get("summary")
    if isinstance(summary, dict):
        return summary

    passed = sum(1 for check in validation.get("checks", []) if check.get("status") == "passed")
    failed = sum(1 for check in validation.get("checks", []) if check.get("status") == "failed")
    skipped = sum(1 for check in validation.get("checks", []) if check.get("status") == "skipped")

    if failed:
        confidence = "low"
    elif passed and not skipped:
        confidence = "high"
    elif passed or skipped:
        confidence = "medium"
    else:
        confidence = "unknown"

    return {
        "status": "trusted" if validation.get("trusted", True) else "review_required",
        "confidence": confidence,
        "check_counts": {
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        },
        "failed_codes": _failed_validation_codes(validation),
    }
