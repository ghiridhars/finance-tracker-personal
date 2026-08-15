"""
Unified Transaction service.

Handles:
  - Creating unified transactions from parsed statement DTOs.
  - Querying unified transactions with filters.
  - Updating category, tags, notes on unified transactions.
"""
import logging
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.models.transaction import UnifiedTransaction

from app.models.enums import TransactionType, SourceType, StatementType, ReviewStatus
from app.services.categorization_service import auto_categorize

logger = logging.getLogger(__name__)


class UnifiedTransactionService:
    """Service for the unified_transactions table."""

    # ── Creation (called when statements are saved) ──────────

    @staticmethod
    def create_from_parsed(
        db: Session,
        dto,
        *,
        statement_type: StatementType,
        source_type: SourceType,
        statement_audit_id: int,
        bank_name: str | None = None,
        bank_account_id: int | None = None,
        account_identifier: str | None = None,
        review_status: str = ReviewStatus.AUTO_PARSED.value,
        review_reason: str | None = None,
        mismatched_indices: list[int] | None = None,
    ) -> list[UnifiedTransaction]:
        """
        Create unified transaction rows from a parsed statement DTO.

        Works for both credit-card and savings DTOs.  Transactions previously
        linked to this statement_audit_id should have been deleted before
        calling this method (handled by StatementAuditService.save_statement).
        """
        is_cc = statement_type == StatementType.CREDIT_CARD
        txns = getattr(dto, "transactions", [])
        created: list[UnifiedTransaction] = []

        mismatched_set = set(mismatched_indices) if mismatched_indices else set()

        for idx, tx in enumerate(txns):
            description = getattr(tx, "description", None)

            if is_cc:
                amount = getattr(tx, "amount", Decimal("0"))
                tx_type = getattr(tx, "type", None)
            else:
                withdrawal = getattr(tx, "withdrawal_amount", None)
                deposit = getattr(tx, "deposit_amount", None)
                if withdrawal and withdrawal > 0:
                    amount = abs(withdrawal)
                    tx_type = TransactionType.DEBIT
                elif deposit and deposit > 0:
                    amount = abs(deposit)
                    tx_type = TransactionType.CREDIT
                else:
                    amount = Decimal("0")
                    tx_type = getattr(tx, "type", None)

            class_result, is_own_transfer = auto_categorize(
                db,
                description=description,
                amount=amount,
                bank_name=bank_name,
                tx_type=tx_type.value if tx_type else None,
            )

            category_id = None
            if idx in mismatched_set:
                review_status_to_use = ReviewStatus.NEEDS_REVIEW.value
                review_reason_to_use = "PARTIAL_BALANCE_MISMATCH"
            else:
                review_status_to_use = review_status
                review_reason_to_use = review_reason
                if class_result.confidence >= 0.85 or class_result.category_id is not None:
                    category_id = class_result.category_id
                    if review_status_to_use == ReviewStatus.NEEDS_REVIEW.value:
                        review_status_to_use = ReviewStatus.AUTO_PARSED.value
                else:
                    review_status_to_use = ReviewStatus.NEEDS_REVIEW.value

            # Resolve directional account IDs for own-UPI single-sided transfers.
            # For a DEBIT: money leaves bank_account_id → to_account_id = resolved target.
            # For a CREDIT: money arrives into bank_account_id → from_account_id = resolved target.
            from_account_id_new: int | None = None
            to_account_id_new: int | None = None
            if is_own_transfer and class_result.target_bank_account_id:
                if tx_type == TransactionType.DEBIT:
                    from_account_id_new = bank_account_id
                    to_account_id_new = class_result.target_bank_account_id
                elif tx_type == TransactionType.CREDIT:
                    from_account_id_new = class_result.target_bank_account_id
                    to_account_id_new = bank_account_id

            unified = UnifiedTransaction(
                date=getattr(tx, "date", None),
                description=description,
                amount=amount,
                type=tx_type,
                source_type=source_type,
                statement_audit_id=statement_audit_id,
                bank=bank_name,
                account_identifier=account_identifier,
                bank_account_id=bank_account_id,
                category_id=category_id,
                suggested_category_id=class_result.category_id,
                classification_source=class_result.source,
                classification_confidence=class_result.confidence,
                merchant_name=class_result.merchant_name,
                reference_number=getattr(tx, "reference_number", None),
                is_transfer=is_own_transfer,
                from_account_id=from_account_id_new,
                to_account_id=to_account_id_new,
                review_status=review_status_to_use,
                review_reason=review_reason_to_use,
            )
            db.add(unified)
            created.append(unified)

        if created:
            db.flush()
            logger.info(
                f"Created {len(created)} unified transactions from "
                f"{statement_type.value} statement (audit_id={statement_audit_id})"
            )
            _run_transfer_detection(db, created)
        return created

    # ── Shared filter builder ────────────────────────────────

    @staticmethod
    def _apply_filters(
        q,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
        category_id: int | None = None,
        bank: str | None = None,
        bank_account_id: int | None = None,
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
        review_status: ReviewStatus | None = None,
        search: str | None = None,
        min_amount: Decimal | None = None,
        max_amount: Decimal | None = None,
    ):
        """Apply the standard filter chain to a query. Used by query() and count()."""
        if from_date:
            q = q.filter(UnifiedTransaction.date >= from_date)
        if to_date:
            q = q.filter(UnifiedTransaction.date <= to_date)
        if category_id is not None:
            q = q.filter(UnifiedTransaction.category_id == category_id)
        if bank:
            q = q.filter(UnifiedTransaction.bank == bank)
        if bank_account_id is not None:
            q = q.filter(UnifiedTransaction.bank_account_id == bank_account_id)
        if account_identifier:
            q = q.filter(UnifiedTransaction.account_identifier == account_identifier)
        if source_type:
            q = q.filter(UnifiedTransaction.source_type == source_type)
        if is_transfer is not None:
            q = q.filter(UnifiedTransaction.is_transfer == is_transfer)
        if tx_type:
            q = q.filter(UnifiedTransaction.type == tx_type)
        if review_status:
            q = q.filter(UnifiedTransaction.review_status == review_status.value)
        if search:
            pattern = f"%{search}%"
            q = q.filter(
                or_(
                    UnifiedTransaction.description.ilike(pattern),
                    UnifiedTransaction.merchant_name.ilike(pattern),
                )
            )
        if min_amount is not None:
            q = q.filter(UnifiedTransaction.amount >= min_amount)
        if max_amount is not None:
            q = q.filter(UnifiedTransaction.amount <= max_amount)
        return q

    # ── Querying ─────────────────────────────────────────────

    @staticmethod
    def query(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
        category_id: int | None = None,
        bank: str | None = None,
        bank_account_id: int | None = None,
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
        review_status: ReviewStatus | None = None,
        search: str | None = None,
        min_amount: Decimal | None = None,
        max_amount: Decimal | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[UnifiedTransaction]:
        q = UnifiedTransactionService._apply_filters(
            db.query(UnifiedTransaction),
            from_date=from_date, to_date=to_date,
            category_id=category_id, bank=bank,
            bank_account_id=bank_account_id,
            account_identifier=account_identifier,
            source_type=source_type, is_transfer=is_transfer, tx_type=tx_type,
            review_status=review_status,
            search=search, min_amount=min_amount, max_amount=max_amount,
        )
        q = q.order_by(UnifiedTransaction.date.desc(), UnifiedTransaction.id.desc())
        return q.offset(offset).limit(limit).all()

    @staticmethod
    def count(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
        category_id: int | None = None,
        bank: str | None = None,
        bank_account_id: int | None = None,
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
        review_status: ReviewStatus | None = None,
        search: str | None = None,
        min_amount: Decimal | None = None,
        max_amount: Decimal | None = None,
    ) -> int:
        """Count matching transactions (for pagination metadata)."""
        q = UnifiedTransactionService._apply_filters(
            db.query(UnifiedTransaction),
            from_date=from_date, to_date=to_date,
            category_id=category_id, bank=bank,
            bank_account_id=bank_account_id,
            account_identifier=account_identifier,
            source_type=source_type, is_transfer=is_transfer, tx_type=tx_type,
            review_status=review_status,
            search=search, min_amount=min_amount, max_amount=max_amount,
        )
        return q.count()

    @staticmethod
    def get_by_id(db: Session, transaction_id: int) -> Optional[UnifiedTransaction]:
        return db.query(UnifiedTransaction).filter(UnifiedTransaction.id == transaction_id).first()

    # ── Update (re-categorize, add tags/notes) ───────────────

    @staticmethod
    def update(
        db: Session,
        transaction_id: int,
        *,
        category_id: int | None = ...,
        merchant_name: str | None = ...,
        notes: str | None = ...,
        review_status: ReviewStatus | None = ...,
        classification_source: str | None = ...,
        classification_confidence: float | None = ...,
        from_account_id: int | None = ...,
        to_account_id: int | None = ...,
    ) -> Optional[UnifiedTransaction]:
        """
        Update a unified transaction's metadata.
        Uses sentinel `...` to distinguish "not provided" from "set to None".
        """
        tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == transaction_id).first()
        if not tx:
            return None

        from app.models.category import Category
        self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
        self_transfer_cat_id = self_transfer_cat.id if self_transfer_cat else None

        if category_id is not ...:
            tx.category_id = category_id
            if self_transfer_cat_id and category_id == self_transfer_cat_id:
                tx.is_transfer = True
        if merchant_name is not ...:
            tx.merchant_name = merchant_name
        if notes is not ...:
            tx.notes = notes
        if review_status is not ...:
            tx.review_status = review_status.value if review_status else None
        if classification_source is not ...:
            tx.classification_source = classification_source
        if classification_confidence is not ...:
            tx.classification_confidence = classification_confidence
        if from_account_id is not ...:
            tx.from_account_id = from_account_id
        if to_account_id is not ...:
            tx.to_account_id = to_account_id

        # Sync counterpart transaction if part of a transfer pair
        if tx.transfer_group_id and (from_account_id is not ... or to_account_id is not ...):
            counterparts = (
                db.query(UnifiedTransaction)
                .filter(
                    UnifiedTransaction.transfer_group_id == tx.transfer_group_id,
                    UnifiedTransaction.id != tx.id,
                )
                .all()
            )
            for cp in counterparts:
                if from_account_id is not ...:
                    cp.from_account_id = from_account_id
                if to_account_id is not ...:
                    cp.to_account_id = to_account_id

        db.commit()
        db.refresh(tx)
        return tx

    @staticmethod
    def bulk_update(db: Session, updates: list) -> int:
        """
        Bulk update multiple transactions efficiently.
        Expects a list of UpdateItem objects.
        Returns the number of rows updated.
        """
        if not updates:
            return 0
            
        from app.models.category import Category
        self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
        self_transfer_cat_id = self_transfer_cat.id if self_transfer_cat else None

        updated_count = 0
        for item in updates:
            tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == item.id).first()
            if not tx:
                continue
                
            if item.category_id is not None:
                tx.category_id = item.category_id
                if self_transfer_cat_id and item.category_id == self_transfer_cat_id:
                    tx.is_transfer = True
            if item.merchant_name is not None:
                tx.merchant_name = item.merchant_name
            if item.notes is not None:
                tx.notes = item.notes
            if item.review_status is not None:
                tx.review_status = item.review_status.value
            if getattr(item, "from_account_id", None) is not None:
                tx.from_account_id = item.from_account_id
            if getattr(item, "to_account_id", None) is not None:
                tx.to_account_id = item.to_account_id

            # Sync counterpart transaction if part of a transfer pair
            if tx.transfer_group_id and (getattr(item, "from_account_id", None) is not None or getattr(item, "to_account_id", None) is not None):
                counterparts = (
                    db.query(UnifiedTransaction)
                    .filter(
                        UnifiedTransaction.transfer_group_id == tx.transfer_group_id,
                        UnifiedTransaction.id != tx.id,
                    )
                    .all()
                )
                for cp in counterparts:
                    if getattr(item, "from_account_id", None) is not None:
                        cp.from_account_id = item.from_account_id
                    if getattr(item, "to_account_id", None) is not None:
                        cp.to_account_id = item.to_account_id

            updated_count += 1
            
        db.commit()
        return updated_count

    @staticmethod
    def auto_resolve_similar(
        db: Session,
        learned_mappings: list[dict],
        exclude_ids: set[int],
    ) -> int:
        """
        After review approvals teach UPI mappings, scan remaining NEEDS_REVIEW
        transactions for the same UPI handles and auto-resolve them.

        Only updates category_id and review_status — merchant_name is left
        as-is to preserve the parser-normalised value already on the record.

        Returns the count of auto-resolved transactions.
        """
        if not learned_mappings:
            return 0

        from app.models.category import Category
        self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
        self_transfer_cat_id = self_transfer_cat.id if self_transfer_cat else None

        resolved = 0
        for mapping in learned_mappings:
            handle = mapping.get("handle")
            category_id = mapping.get("category_id")
            if not handle or category_id is None:
                continue

            pending = (
                db.query(UnifiedTransaction)
                .filter(
                    UnifiedTransaction.review_status == ReviewStatus.NEEDS_REVIEW.value,
                    UnifiedTransaction.description.ilike(f"%{handle}%"),
                )
                .all()
            )
            for tx in pending:
                if tx.id in exclude_ids:
                    continue
                tx.category_id = category_id
                if self_transfer_cat_id and category_id == self_transfer_cat_id:
                    tx.is_transfer = True
                tx.review_status = ReviewStatus.REVIEWED.value
                resolved += 1

        if resolved:
            db.commit()
            logger.info(
                f"Auto-resolved {resolved} similar NEEDS_REVIEW transaction(s) "
                "after review approval"
            )

        return resolved

    @staticmethod
    def auto_resolve_by_keywords(
        db: Session,
        learned_keywords: list[dict],
        exclude_ids: set[int],
    ) -> int:
        """
        After keyword learning, scan remaining NEEDS_REVIEW transactions whose
        descriptions contain the newly learned keywords and auto-resolve them.

        This is the keyword-tier complement of :meth:`auto_resolve_similar`
        (which handles UPI handles).  Together they ensure that both UPI and
        non-UPI transactions in the review queue benefit immediately from a
        user correction.

        Args:
            db: Active SQLAlchemy session.
            learned_keywords: List of ``{"keyword": str, "category_id": int}`` dicts.
            exclude_ids: Transaction IDs that were just updated — skip them to
                         avoid double-counting.

        Returns:
            Count of auto-resolved transactions.
        """
        if not learned_keywords:
            return 0

        from app.models.category import Category
        self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
        self_transfer_cat_id = self_transfer_cat.id if self_transfer_cat else None

        resolved = 0
        for mapping in learned_keywords:
            keyword = mapping.get("keyword")
            category_id = mapping.get("category_id")
            if not keyword or category_id is None:
                continue

            pending = (
                db.query(UnifiedTransaction)
                .filter(
                    UnifiedTransaction.review_status == ReviewStatus.NEEDS_REVIEW.value,
                    UnifiedTransaction.description.ilike(f"%{keyword}%"),
                )
                .all()
            )
            for tx in pending:
                if tx.id in exclude_ids:
                    continue
                tx.category_id = category_id
                if self_transfer_cat_id and category_id == self_transfer_cat_id:
                    tx.is_transfer = True
                tx.review_status = ReviewStatus.REVIEWED.value
                resolved += 1

        if resolved:
            db.commit()
            logger.info(
                f"Auto-resolved {resolved} NEEDS_REVIEW transaction(s) "
                "via keyword learning"
            )

        return resolved



    # ── Bulk re-categorize ───────────────────────────────────

    @staticmethod
    def recategorize_all(db: Session) -> int:
        """
        Re-run auto-categorization on ALL unified transactions.
        Useful after adding new keywords.
        Returns count of transactions updated.
        """
        from app.services.categorization_service import auto_categorize

        transactions = db.query(UnifiedTransaction).filter(UnifiedTransaction.review_status != ReviewStatus.REVIEWED.value).all()
        updated = 0
        for tx in transactions:
            class_result, is_own_transfer = auto_categorize(
                db,
                description=tx.description,
                amount=tx.amount,
                bank_name=tx.bank,
                tx_type=tx.type.value if tx.type else None,
            )
            changed = False

            # Apply same acceptance logic as create_from_parsed
            new_cat_id = None
            if class_result.confidence >= 0.85:
                new_cat_id = class_result.category_id

            if new_cat_id and tx.category_id != new_cat_id:
                tx.category_id = new_cat_id
                tx.classification_source = class_result.source
                tx.classification_confidence = class_result.confidence
                tx.review_status = ReviewStatus.AUTO_PARSED.value
                changed = True

            if class_result.category_id and tx.suggested_category_id != class_result.category_id:
                tx.suggested_category_id = class_result.category_id
                tx.classification_source = class_result.source
                tx.classification_confidence = class_result.confidence
                changed = True

            if class_result.merchant_name and tx.merchant_name != class_result.merchant_name:
                tx.merchant_name = class_result.merchant_name
                changed = True
            if is_own_transfer and not tx.is_transfer:
                tx.is_transfer = True
                changed = True
            # Backfill from/to account IDs if not yet set and now resolvable
            if is_own_transfer and class_result.target_bank_account_id:
                if tx.type == TransactionType.DEBIT and tx.to_account_id is None:
                    tx.from_account_id = tx.bank_account_id
                    tx.to_account_id = class_result.target_bank_account_id
                    changed = True
                elif tx.type == TransactionType.CREDIT and tx.from_account_id is None:
                    tx.from_account_id = class_result.target_bank_account_id
                    tx.to_account_id = tx.bank_account_id
                    changed = True
            if changed:
                updated += 1

        if updated:
            db.commit()
            logger.info(f"Re-categorized {updated} transactions.")
        return updated


# ── Module-level helper (avoids circular import) ─────────────

def _run_transfer_detection(db: Session, transactions: list[UnifiedTransaction]) -> None:
    """Run transfer detection for newly created transactions (best-effort)."""
    try:
        from app.services.transfer_detection_service import TransferDetectionService

        tx_ids = [tx.id for tx in transactions]
        pairs = TransferDetectionService.detect_for_transactions(db, tx_ids)
        if pairs:
            logger.info(f"Auto-linked {len(pairs)} transfer pair(s) after upload")
    except Exception:
        logger.warning("Transfer detection failed after upload", exc_info=True)

