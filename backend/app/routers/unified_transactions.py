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
from app.models.enums import TransactionType, SourceType, ReviewStatus
from app.models.transaction import UnifiedTransaction
from app.services.transaction_service import UnifiedTransactionService
from app.services.accounts_service import StatementManagementService
from app.schemas.transaction import (
    UnifiedTransactionSchema,
    TransactionUpdateSchema,
    BulkTransactionUpdateSchema,
    BulkUpdateResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/transactions", tags=["Unified Transactions"])


@router.get("", response_model=list[UnifiedTransactionSchema])
def list_transactions(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    category_id: Optional[int] = Query(None),
    bank: Optional[str] = Query(None),
    bank_account_id: Optional[int] = Query(None),
    account_identifier: Optional[str] = Query(None),
    source_type: Optional[SourceType] = Query(None),
    is_transfer: Optional[bool] = Query(None),
    tx_type: Optional[TransactionType] = Query(None, alias="type"),
    review_status: Optional[ReviewStatus] = Query(None),
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
    transactions = UnifiedTransactionService.query(
        db,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        bank=bank,
        bank_account_id=bank_account_id,
        account_identifier=account_identifier,
        source_type=source_type,
        is_transfer=is_transfer,
        tx_type=tx_type,
        review_status=review_status,
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
    bank_account_id: Optional[int] = Query(None),
    account_identifier: Optional[str] = Query(None),
    source_type: Optional[SourceType] = Query(None),
    is_transfer: Optional[bool] = Query(None),
    tx_type: Optional[TransactionType] = Query(None, alias="type"),
    review_status: Optional[ReviewStatus] = Query(None),
    search: Optional[str] = Query(None),
    min_amount: Optional[Decimal] = Query(None),
    max_amount: Optional[Decimal] = Query(None),
    db: Session = Depends(get_db),
):
    """Count matching transactions (for pagination metadata)."""
    total = UnifiedTransactionService.count(
        db,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        bank=bank,
        bank_account_id=bank_account_id,
        account_identifier=account_identifier,
        source_type=source_type,
        is_transfer=is_transfer,
        tx_type=tx_type,
        review_status=review_status,
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
    Update category, merchant name, or notes on a unified transaction.
    Use this for manual re-categorization.

    Self-improving: When the user changes the category, the system learns
    the UPI handle → category mapping for future auto-categorization.
    """
    kwargs = {}
    if data.category_id is not None:
        kwargs["category_id"] = data.category_id
    if data.merchant_name is not None:
        kwargs["merchant_name"] = data.merchant_name
    if data.notes is not None:
        kwargs["notes"] = data.notes
    if data.review_status is not None:
        kwargs["review_status"] = data.review_status
    if data.from_account_id is not None:
        kwargs["from_account_id"] = data.from_account_id
    if data.to_account_id is not None:
        kwargs["to_account_id"] = data.to_account_id
        
    # If a user explicitly changes the category via the standard update endpoint
    if data.category_id is not None:
        from app.models.enums import ClassificationSource
        kwargs["classification_source"] = ClassificationSource.USER_DIRECT.value
        kwargs["classification_confidence"] = 1.0

    tx = UnifiedTransactionService.update(db, transaction_id, **kwargs)
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    # Self-improving: learn from the user's category choice (both tiers)
    if data.category_id is not None and tx.description:
        from app.services.categorization_service import learn_from_categorization
        learned_handle, learned_keyword = learn_from_categorization(
            db, tx.description, data.category_id
        )
        if learned_handle or learned_keyword:
            logger.info(
                "Learned category mapping from user correction on tx %d "
                "(handle=%s, keyword=%s)",
                transaction_id, learned_handle, learned_keyword,
            )
            # Auto-resolve similar NEEDS_REVIEW transactions immediately
            if learned_handle:
                UnifiedTransactionService.auto_resolve_similar(
                    db, [{"handle": learned_handle, "category_id": data.category_id}], {transaction_id}
                )
            if learned_keyword:
                UnifiedTransactionService.auto_resolve_by_keywords(
                    db, [{"keyword": learned_keyword, "category_id": data.category_id}], {transaction_id}
                )

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


@router.post("/bulk-update", response_model=BulkUpdateResponse)
def bulk_update(data: BulkTransactionUpdateSchema, db: Session = Depends(get_db)):
    """
    Bulk update transactions from the review pane.
    Also handles individual saves — the review pane always sends a single-item
    list when the user approves one transaction at a time.

    Two-tier self-improving learning runs after every save:

    **Tier 1 — UPI handle learning**: for UPI transactions, the handle is
    persisted as a learned mapping so future statements are auto-categorised
    without triggering a review.

    **Tier 2 — Keyword learning**: for NEFT / IMPS / POS / bank transfers
    (no UPI handle), a normalized keyword phrase is extracted from the
    description and saved to ``category_keywords``.  Future transactions
    matching that phrase are auto-categorised via the keyword-match path.

    **Auto-propagation**: after learning, any other NEEDS_REVIEW transactions
    sharing the same UPI handles *or* matching the newly learned keywords are
    resolved automatically, shrinking the review queue without additional
    user action.
    """
    from app.services.categorization_service import learn_from_categorization

    # Pre-fetch descriptions before the bulk commit so learning survives
    # SQLAlchemy session expiry after the bulk update commit.
    ids = [item.id for item in data.updates]
    desc_map: dict[int, str | None] = {}
    if ids:
        rows = (
            db.query(UnifiedTransaction.id, UnifiedTransaction.description)
            .filter(UnifiedTransaction.id.in_(ids))
            .all()
        )
        desc_map = {row.id: row.description for row in rows}

    from app.models.enums import ClassificationSource
    for item in data.updates:
        if item.category_id is not None:
            item.classification_source = ClassificationSource.USER_REVIEW.value
            item.classification_confidence = 1.0

    # Perform the actual bulk update (commits inside).
    count = UnifiedTransactionService.bulk_update(db, data.updates)

    # ── Two-tier learning: collect what was learned ────────────────────────
    # Use dicts to deduplicate by handle/keyword so we don't run redundant sweeps
    learned_upi_dict: dict[str, dict] = {}
    learned_kw_dict: dict[str, dict] = {}

    for item in data.updates:
        if item.category_id is None:
            continue
        description = desc_map.get(item.id)
        if not description:
            continue

        learned_handle, learned_keyword = learn_from_categorization(
            db, description, item.category_id
        )

        if learned_handle:
            learned_upi_dict[learned_handle] = {
                "handle": learned_handle, 
                "category_id": item.category_id
            }
        if learned_keyword:
            learned_kw_dict[learned_keyword] = {
                "keyword": learned_keyword, 
                "category_id": item.category_id
            }

    learned_upi_mappings = list(learned_upi_dict.values())
    learned_kw_mappings = list(learned_kw_dict.values())

    if learned_upi_mappings:
        logger.info(
            "Learned %d unique UPI mapping(s) from review approval",
            len(learned_upi_mappings),
        )
    if learned_kw_mappings:
        logger.info(
            "Learned %d unique keyword mapping(s) from review approval",
            len(learned_kw_mappings),
        )

    # ── Auto-propagate: resolve other NEEDS_REVIEW txns in the queue ──────
    exclude_ids = set(ids)

    auto_resolved = UnifiedTransactionService.auto_resolve_similar(
        db, learned_upi_mappings, exclude_ids
    )
    auto_resolved += UnifiedTransactionService.auto_resolve_by_keywords(
        db, learned_kw_mappings, exclude_ids
    )

    return BulkUpdateResponse(updated=count, auto_resolved=auto_resolved)
