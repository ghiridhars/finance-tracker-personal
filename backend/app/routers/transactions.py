"""
Legacy transaction query endpoint.
Redirects to unified_transactions for backward compatibility.
"""
import logging
from datetime import date

from fastapi import APIRouter, Query, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.transaction import UnifiedTransaction
from app.models.enums import SourceType

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/transactions", tags=["Transactions (legacy)"])


@router.get("/savings")
def get_savings_transactions(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """Legacy savings transactions endpoint — queries unified_transactions."""
    q = db.query(UnifiedTransaction).filter(
        UnifiedTransaction.source_type == SourceType.SAVINGS
    )
    if from_date:
        q = q.filter(UnifiedTransaction.date >= from_date)
    if to_date:
        q = q.filter(UnifiedTransaction.date <= to_date)
    return [_tx_to_dict(t) for t in q.order_by(UnifiedTransaction.date.desc()).all()]


@router.get("/credit-card")
def get_credit_card_transactions(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """Legacy credit card transactions endpoint — queries unified_transactions."""
    q = db.query(UnifiedTransaction).filter(
        UnifiedTransaction.source_type == SourceType.CREDIT_CARD
    )
    if from_date:
        q = q.filter(UnifiedTransaction.date >= from_date)
    if to_date:
        q = q.filter(UnifiedTransaction.date <= to_date)
    return [_tx_to_dict(t) for t in q.order_by(UnifiedTransaction.date.desc()).all()]


@router.get("")
def get_transactions_default(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """Legacy default endpoint — returns all unified transactions."""
    q = db.query(UnifiedTransaction)
    if from_date:
        q = q.filter(UnifiedTransaction.date >= from_date)
    if to_date:
        q = q.filter(UnifiedTransaction.date <= to_date)
    return [_tx_to_dict(t) for t in q.order_by(UnifiedTransaction.date.desc()).all()]


def _tx_to_dict(tx: UnifiedTransaction) -> dict:
    return {
        "id": tx.id,
        "date": tx.date.isoformat() if tx.date else None,
        "description": tx.description,
        "amount": float(tx.amount) if tx.amount else None,
        "type": tx.type,
        "bank": tx.bank,
        "account_identifier": tx.account_identifier,
        "reference_number": tx.reference_number,
        "source_type": tx.source_type,
        "review_status": tx.review_status,
    }
