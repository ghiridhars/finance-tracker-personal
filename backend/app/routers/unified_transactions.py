"""
Unified Transaction query + update endpoints.
"""
import logging
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.enums import TransactionType, SourceType
from app.services.transaction_service import UnifiedTransactionService
from app.services.accounts_service import StatementManagementService
from app.schemas.transaction import UnifiedTransactionSchema, TransactionUpdateSchema

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/transactions", tags=["Unified Transactions"])


@router.get("", response_model=list[UnifiedTransactionSchema])
def list_transactions(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    category_id: Optional[int] = Query(None),
    bank: Optional[str] = Query(None),
    source_type: Optional[SourceType] = Query(None),
    tx_type: Optional[TransactionType] = Query(None, alias="type"),
    search: Optional[str] = Query(None),
    min_amount: Optional[Decimal] = Query(None),
    max_amount: Optional[Decimal] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """
    Query unified transactions with optional filters.
    Defaults: last 90 days if no date range specified.
    """
    if from_date is None:
        from_date = date.today() - timedelta(days=90)
    if to_date is None:
        to_date = date.today()

    transactions = UnifiedTransactionService.query(
        db,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        bank=bank,
        source_type=source_type,
        tx_type=tx_type,
        search=search,
        min_amount=min_amount,
        max_amount=max_amount,
        limit=limit,
        offset=offset,
    )
    return [UnifiedTransactionSchema.model_validate(t) for t in transactions]


@router.get("/count")
def count_transactions(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    category_id: Optional[int] = Query(None),
    bank: Optional[str] = Query(None),
    source_type: Optional[SourceType] = Query(None),
    tx_type: Optional[TransactionType] = Query(None, alias="type"),
    search: Optional[str] = Query(None),
    min_amount: Optional[Decimal] = Query(None),
    max_amount: Optional[Decimal] = Query(None),
    db: Session = Depends(get_db),
):
    """Count matching transactions (for pagination metadata)."""
    if from_date is None:
        from_date = date.today() - timedelta(days=90)
    if to_date is None:
        to_date = date.today()

    total = UnifiedTransactionService.count(
        db,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        bank=bank,
        source_type=source_type,
        tx_type=tx_type,
        search=search,
        min_amount=min_amount,
        max_amount=max_amount,
    )
    return {"total": total}


@router.get("/{transaction_id}", response_model=UnifiedTransactionSchema)
def get_transaction(transaction_id: int, db: Session = Depends(get_db)):
    tx = UnifiedTransactionService.get_by_id(db, transaction_id)
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return UnifiedTransactionSchema.model_validate(tx)


@router.patch("/{transaction_id}", response_model=UnifiedTransactionSchema)
def update_transaction(
    transaction_id: int,
    data: TransactionUpdateSchema,
    db: Session = Depends(get_db),
):
    """
    Update category, merchant name, notes, or tags on a unified transaction.
    Use this for manual re-categorization.
    """
    kwargs = {}
    if data.category_id is not None:
        kwargs["category_id"] = data.category_id
    if data.merchant_name is not None:
        kwargs["merchant_name"] = data.merchant_name
    if data.notes is not None:
        kwargs["notes"] = data.notes
    if data.tag_ids is not None:
        kwargs["tag_ids"] = data.tag_ids

    tx = UnifiedTransactionService.update(db, transaction_id, **kwargs)
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return UnifiedTransactionSchema.model_validate(tx)


@router.post("/{transaction_id}/tags/{tag_id}", response_model=UnifiedTransactionSchema)
def add_tag(transaction_id: int, tag_id: int, db: Session = Depends(get_db)):
    tx = UnifiedTransactionService.add_tag(db, transaction_id, tag_id)
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction or tag not found")
    return UnifiedTransactionSchema.model_validate(tx)


@router.delete("/{transaction_id}/tags/{tag_id}", response_model=UnifiedTransactionSchema)
def remove_tag(transaction_id: int, tag_id: int, db: Session = Depends(get_db)):
    tx = UnifiedTransactionService.remove_tag(db, transaction_id, tag_id)
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction or tag not found")
    return UnifiedTransactionSchema.model_validate(tx)


@router.delete("/{transaction_id}")
def delete_transaction(transaction_id: int, db: Session = Depends(get_db)):
    """Delete a single unified transaction."""
    deleted = StatementManagementService.delete_unified_transaction(db, transaction_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return {"detail": "Transaction deleted", "id": transaction_id}


@router.post("/recategorize")
def recategorize_all(db: Session = Depends(get_db)):
    """Re-run auto-categorization on all unified transactions (e.g. after adding keywords)."""
    count = UnifiedTransactionService.recategorize_all(db)
    return {"updated": count}
