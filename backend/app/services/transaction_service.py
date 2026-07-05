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
from app.models.tag import Tag, TransactionTag
from app.models.enums import TransactionType, SourceType, StatementType, ReviewStatus
from app.models.category import CategoryKeyword
from app.services.categorization_service import categorize_and_normalize

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

        keywords = db.query(CategoryKeyword).all()
        keywords.sort(key=lambda k: len(k.keyword), reverse=True)

        for tx in txns:
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

            category_id, merchant_name, is_own_transfer = categorize_and_normalize(
                db, description, keywords=keywords
            )

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
                merchant_name=merchant_name,
                reference_number=getattr(tx, "reference_number", None),
                is_transfer=is_own_transfer,
                review_status=review_status,
                review_reason=review_reason,
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
        tag_ids: list[int] | None = None,
        review_status: ReviewStatus | None = ...,
    ) -> Optional[UnifiedTransaction]:
        """
        Update a unified transaction's metadata.
        Uses sentinel `...` to distinguish "not provided" from "set to None".
        """
        tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == transaction_id).first()
        if not tx:
            return None

        if category_id is not ...:
            tx.category_id = category_id
        if merchant_name is not ...:
            tx.merchant_name = merchant_name
        if notes is not ...:
            tx.notes = notes
        if review_status is not ...:
            tx.review_status = review_status.value if review_status else None

        if tag_ids is not None:
            # Replace tags
            tags = db.query(Tag).filter(Tag.id.in_(tag_ids)).all()
            tx.tags = tags

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
            
        updated_count = 0
        for item in updates:
            tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == item.id).first()
            if not tx:
                continue
                
            if item.category_id is not None:
                tx.category_id = item.category_id
            if item.merchant_name is not None:
                tx.merchant_name = item.merchant_name
            if item.notes is not None:
                tx.notes = item.notes
            if item.review_status is not None:
                tx.review_status = item.review_status.value
            
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
    def add_tag(db: Session, transaction_id: int, tag_id: int) -> Optional[UnifiedTransaction]:
        tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == transaction_id).first()
        tag = db.query(Tag).filter(Tag.id == tag_id).first()
        if not tx or not tag:
            return None
        if tag not in tx.tags:
            tx.tags.append(tag)
            db.commit()
            db.refresh(tx)
        return tx

    @staticmethod
    def remove_tag(db: Session, transaction_id: int, tag_id: int) -> Optional[UnifiedTransaction]:
        tx = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == transaction_id).first()
        tag = db.query(Tag).filter(Tag.id == tag_id).first()
        if not tx or not tag:
            return None
        if tag in tx.tags:
            tx.tags.remove(tag)
            db.commit()
            db.refresh(tx)
        return tx

    # ── Bulk re-categorize ───────────────────────────────────

    @staticmethod
    def recategorize_all(db: Session) -> int:
        """
        Re-run auto-categorization on ALL unified transactions.
        Useful after adding new keywords.
        Returns count of transactions updated.
        """
        from app.services.categorization_service import categorize_and_normalize
        from app.models.category import CategoryKeyword

        transactions = db.query(UnifiedTransaction).all()
        keywords = db.query(CategoryKeyword).all()
        keywords.sort(key=lambda k: len(k.keyword), reverse=True)
        updated = 0
        for tx in transactions:
            new_cat_id, new_merchant, is_own_transfer = categorize_and_normalize(db, tx.description, keywords=keywords)
            changed = False
            if new_cat_id and tx.category_id != new_cat_id:
                tx.category_id = new_cat_id
                changed = True
            if new_merchant and tx.merchant_name != new_merchant:
                tx.merchant_name = new_merchant
                changed = True
            if is_own_transfer and not tx.is_transfer:
                tx.is_transfer = True
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
