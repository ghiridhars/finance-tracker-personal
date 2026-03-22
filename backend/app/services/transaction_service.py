"""
Unified Transaction service.

Handles:
  - Creating unified transactions from credit card / savings source transactions.
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
from app.models.enums import TransactionType, SourceType
from app.models.credit_card import CreditCardStatement, CreditCardTransaction
from app.models.savings_account import SavingsAccountStatement, SavingsAccountTransaction
from app.services.categorization_service import categorize_and_normalize

logger = logging.getLogger(__name__)


class UnifiedTransactionService:
    """Service for the unified_transactions table."""

    # ── Creation (called when statements are saved) ──────────

    @staticmethod
    def create_from_credit_card(
        db: Session,
        statement: CreditCardStatement,
        bank: str | None = None,
    ) -> list[UnifiedTransaction]:
        """
        Create unified transaction rows for each credit card transaction.
        Upserts: skips rows that already exist (source_type + source_transaction_id).
        """
        created: list[UnifiedTransaction] = []
        for tx in statement.transactions:
            existing = (
                db.query(UnifiedTransaction)
                .filter(
                    UnifiedTransaction.source_type == SourceType.CREDIT_CARD,
                    UnifiedTransaction.source_transaction_id == tx.id,
                )
                .first()
            )
            if existing:
                continue

            category_id, merchant_name, is_own_transfer = categorize_and_normalize(db, tx.description)

            unified = UnifiedTransaction(
                date=tx.date,
                description=tx.description,
                amount=tx.amount,
                type=tx.type,
                source_type=SourceType.CREDIT_CARD,
                source_transaction_id=tx.id,
                bank=bank,
                account_identifier=statement.card_number,
                category_id=category_id,
                merchant_name=merchant_name,
                reference_number=tx.reference_number,
                is_transfer=is_own_transfer,
            )
            db.add(unified)
            created.append(unified)

        if created:
            db.commit()
            for u in created:
                db.refresh(u)
            logger.info(
                f"Created {len(created)} unified transactions from CC statement "
                f"(card={statement.card_number})"
            )
            # Auto-detect transfer pairs for newly created transactions
            _run_transfer_detection(db, created)
        return created

    @staticmethod
    def create_from_savings(
        db: Session,
        statement: SavingsAccountStatement,
        bank: str | None = None,
    ) -> list[UnifiedTransaction]:
        """
        Create unified transaction rows for each savings transaction.
        """
        created: list[UnifiedTransaction] = []
        for tx in statement.transactions:
            existing = (
                db.query(UnifiedTransaction)
                .filter(
                    UnifiedTransaction.source_type == SourceType.SAVINGS,
                    UnifiedTransaction.source_transaction_id == tx.id,
                )
                .first()
            )
            if existing:
                continue

            # Normalize amount: always positive, type indicates direction
            if tx.withdrawal_amount and tx.withdrawal_amount > 0:
                amount = abs(tx.withdrawal_amount)
                tx_type = TransactionType.DEBIT
            elif tx.deposit_amount and tx.deposit_amount > 0:
                amount = abs(tx.deposit_amount)
                tx_type = TransactionType.CREDIT
            else:
                amount = Decimal("0")
                tx_type = tx.type

            category_id, merchant_name, is_own_transfer = categorize_and_normalize(db, tx.description)

            unified = UnifiedTransaction(
                date=tx.date,
                description=tx.description,
                amount=amount,
                type=tx_type,
                source_type=SourceType.SAVINGS,
                source_transaction_id=tx.id,
                bank=bank,
                account_identifier=statement.account_number,
                category_id=category_id,
                merchant_name=merchant_name,
                reference_number=tx.reference_number,
                is_transfer=is_own_transfer,
            )
            db.add(unified)
            created.append(unified)

        if created:
            db.commit()
            for u in created:
                db.refresh(u)
            logger.info(
                f"Created {len(created)} unified transactions from savings statement "
                f"(account={statement.account_number})"
            )
            # Auto-detect transfer pairs for newly created transactions
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
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
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
        if account_identifier:
            q = q.filter(UnifiedTransaction.account_identifier == account_identifier)
        if source_type:
            q = q.filter(UnifiedTransaction.source_type == source_type)
        if is_transfer is not None:
            q = q.filter(UnifiedTransaction.is_transfer == is_transfer)
        if tx_type:
            q = q.filter(UnifiedTransaction.type == tx_type)
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
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
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
            account_identifier=account_identifier,
            source_type=source_type, is_transfer=is_transfer, tx_type=tx_type,
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
        account_identifier: str | None = None,
        source_type: SourceType | None = None,
        is_transfer: bool | None = None,
        tx_type: TransactionType | None = None,
        search: str | None = None,
        min_amount: Decimal | None = None,
        max_amount: Decimal | None = None,
    ) -> int:
        """Count matching transactions (for pagination metadata)."""
        q = UnifiedTransactionService._apply_filters(
            db.query(UnifiedTransaction),
            from_date=from_date, to_date=to_date,
            category_id=category_id, bank=bank,
            account_identifier=account_identifier,
            source_type=source_type, is_transfer=is_transfer, tx_type=tx_type,
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

        if tag_ids is not None:
            # Replace tags
            tags = db.query(Tag).filter(Tag.id.in_(tag_ids)).all()
            tx.tags = tags

        db.commit()
        db.refresh(tx)
        return tx

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

        transactions = db.query(UnifiedTransaction).all()
        updated = 0
        for tx in transactions:
            new_cat_id, new_merchant, is_own_transfer = categorize_and_normalize(db, tx.description)
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
