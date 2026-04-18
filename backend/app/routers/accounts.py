"""
Accounts & Statement Management router.

Endpoints:
  - GET  /api/v2/accounts                    — List linked accounts/cards
  - PATCH /api/v2/accounts/rename            — Rename an account
  - GET  /api/v2/accounts/statements         — List statements (unified, paginated)
  - DELETE /api/v2/accounts/statements/{id}  — Delete a statement + its transactions
  - DELETE /api/v2/transactions/{id}         — Delete unified transaction
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
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
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """List successful statement imports (paginated). Optionally filter by type or account."""
    items, total = StatementManagementService.list_statements(
        db, statement_type=statement_type, bank_account_id=bank_account_id,
        limit=limit, offset=offset,
    )
    return {
        "items": [_audit_to_dict(s) for s in items],
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


def _audit_to_dict(audit) -> dict:
    """Serialize a StatementAudit row for the API response."""
    return {
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
