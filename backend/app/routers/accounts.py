"""
Accounts & Statement Management router.

Endpoints:
  - GET  /api/v2/accounts                    — List linked accounts/cards
  - GET  /api/v2/accounts/statements/savings  — List savings statements (paginated)
  - GET  /api/v2/accounts/statements/credit-card — List CC statements (paginated)
  - DELETE /api/v2/accounts/statements/savings/{id}  — Delete savings statement
  - DELETE /api/v2/accounts/statements/credit-card/{id} — Delete CC statement
  - DELETE /api/v2/transactions/{id}          — Delete unified transaction
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.accounts_service import AccountsService, StatementManagementService
from app.schemas.savings_account import SavingsAccountStatementSchema
from app.schemas.credit_card import CreditCardStatementSchema

router = APIRouter(prefix="/api/v2/accounts", tags=["Accounts & Statements"])


@router.get("")
def list_accounts(db: Session = Depends(get_db)):
    """
    List all known accounts and credit cards,
    with statement count, transaction count, and latest balance.
    """
    return AccountsService.get_accounts(db)


@router.get("/statements/savings")
def list_savings_statements(
    account_number: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """List savings statements (paginated). Optionally filter by account_number."""
    items, total = StatementManagementService.list_savings_statements(
        db, account_number=account_number, limit=limit, offset=offset
    )
    return {
        "items": [SavingsAccountStatementSchema.model_validate(s) for s in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/statements/credit-card")
def list_cc_statements(
    card_number: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """List credit card statements (paginated). Optionally filter by card_number."""
    items, total = StatementManagementService.list_cc_statements(
        db, card_number=card_number, limit=limit, offset=offset
    )
    return {
        "items": [CreditCardStatementSchema.model_validate(s) for s in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.delete("/statements/savings/{statement_id}")
def delete_savings_statement(statement_id: int, db: Session = Depends(get_db)):
    """Delete a savings statement and all its associated transactions (including unified)."""
    deleted = StatementManagementService.delete_savings_statement(db, statement_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Savings statement not found")
    return {"detail": "Statement deleted", "id": statement_id}


@router.delete("/statements/credit-card/{statement_id}")
def delete_cc_statement(statement_id: int, db: Session = Depends(get_db)):
    """Delete a credit card statement and all its associated transactions (including unified)."""
    deleted = StatementManagementService.delete_cc_statement(db, statement_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Credit card statement not found")
    return {"detail": "Statement deleted", "id": statement_id}
