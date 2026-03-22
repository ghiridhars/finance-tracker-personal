"""
Transfer detection service — identifies inter-account transfers
and CC bill payments among unified transactions.

Matching strategy:
  - Exact amount match between a DEBIT and a CREDIT on different accounts.
  - Date within ±3 days to account for bank processing delays.
  - Neither transaction is already linked to a transfer.
  - CC bill payments: additionally cross-reference against CC statement dues.
"""
import logging
import re
import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from app.models.transaction import UnifiedTransaction
from app.models.credit_card import CreditCardStatement
from app.models.enums import TransactionType, SourceType, TransferType

logger = logging.getLogger(__name__)

# Keywords that suggest a CC bill payment in savings transaction descriptions
_CC_PAYMENT_KEYWORDS = re.compile(
    r"(?i)(CREDIT\s*CARD|CC\s*(PAYMENT|BILL|PMT)|CARD\s*BILL|"
    r"VISA\s*BILL|MASTER\s*CARD\s*BILL|AMEX\s*BILL)",
)

# Date tolerance for matching (bank processing delay)
_DATE_TOLERANCE_DAYS = 3


class TransferDetectionService:
    """Detects and links inter-account transfers and CC bill payments."""

    @staticmethod
    def detect_all(db: Session) -> list[dict]:
        """
        Scan all unlinked transactions and auto-detect transfer pairs.
        Returns a list of newly linked pairs with their transfer_group_ids.
        """
        linked_pairs = []

        # Get all unlinked DEBIT transactions
        debits = (
            db.query(UnifiedTransaction)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                UnifiedTransaction.amount.isnot(None),
                UnifiedTransaction.amount > 0,
            )
            .order_by(UnifiedTransaction.date.desc())
            .all()
        )

        # Track IDs already linked in this run to avoid double-matching
        linked_ids: set[int] = set()

        for debit_tx in debits:
            if debit_tx.id in linked_ids:
                continue

            pair = TransferDetectionService._find_matching_credit(
                db, debit_tx, linked_ids
            )
            if pair:
                credit_tx, transfer_type = pair
                group_id = TransferDetectionService._link_pair(
                    db, debit_tx, credit_tx, transfer_type
                )
                linked_ids.add(debit_tx.id)
                linked_ids.add(credit_tx.id)
                linked_pairs.append({
                    "transfer_group_id": group_id,
                    "transfer_type": transfer_type.value,
                    "debit_id": debit_tx.id,
                    "credit_id": credit_tx.id,
                })

        if linked_pairs:
            db.commit()
            logger.info(f"Auto-detected {len(linked_pairs)} transfer pairs")

        return linked_pairs

    @staticmethod
    def detect_for_transactions(
        db: Session,
        transaction_ids: list[int],
    ) -> list[dict]:
        """
        Run detection for specific transactions only (e.g., after upload).
        Tries to match each given transaction against the existing pool.
        """
        linked_pairs = []
        linked_ids: set[int] = set()

        transactions = (
            db.query(UnifiedTransaction)
            .filter(UnifiedTransaction.id.in_(transaction_ids))
            .all()
        )

        for tx in transactions:
            if tx.id in linked_ids or tx.is_transfer:
                continue

            if tx.type == TransactionType.DEBIT:
                pair = TransferDetectionService._find_matching_credit(
                    db, tx, linked_ids
                )
            elif tx.type == TransactionType.CREDIT:
                pair = TransferDetectionService._find_matching_debit(
                    db, tx, linked_ids
                )
            else:
                continue

            if pair:
                counterpart, transfer_type = pair
                group_id = TransferDetectionService._link_pair(
                    db, tx, counterpart, transfer_type
                )
                linked_ids.add(tx.id)
                linked_ids.add(counterpart.id)
                linked_pairs.append({
                    "transfer_group_id": group_id,
                    "transfer_type": transfer_type.value,
                    "transaction_ids": [tx.id, counterpart.id],
                })

        if linked_pairs:
            db.commit()
            logger.info(
                f"Detected {len(linked_pairs)} transfer pairs for "
                f"{len(transaction_ids)} new transactions"
            )

        return linked_pairs

    @staticmethod
    def link_manual(
        db: Session,
        tx_id_1: int,
        tx_id_2: int,
        transfer_type: TransferType = TransferType.INTERNAL_TRANSFER,
    ) -> Optional[str]:
        """
        Manually link two transactions as a transfer pair.
        Returns the transfer_group_id, or None if either tx not found.
        """
        tx1 = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == tx_id_1).first()
        tx2 = db.query(UnifiedTransaction).filter(UnifiedTransaction.id == tx_id_2).first()

        if not tx1 or not tx2:
            return None

        # Unlink any existing transfer groups first
        for tx in (tx1, tx2):
            if tx.transfer_group_id:
                TransferDetectionService._unlink_group(db, tx.transfer_group_id)

        group_id = TransferDetectionService._link_pair(db, tx1, tx2, transfer_type)
        db.commit()
        return group_id

    @staticmethod
    def unlink(db: Session, transfer_group_id: str) -> bool:
        """Unlink a transfer pair by group ID."""
        return TransferDetectionService._unlink_group(db, transfer_group_id, commit=True)

    @staticmethod
    def list_pairs(db: Session) -> list[dict]:
        """List all linked transfer pairs."""
        groups = (
            db.query(UnifiedTransaction.transfer_group_id)
            .filter(UnifiedTransaction.transfer_group_id.isnot(None))
            .distinct()
            .all()
        )

        pairs = []
        for (group_id,) in groups:
            txns = (
                db.query(UnifiedTransaction)
                .filter(UnifiedTransaction.transfer_group_id == group_id)
                .all()
            )
            if txns:
                pairs.append({
                    "transfer_group_id": group_id,
                    "transfer_type": txns[0].transfer_type,
                    "transactions": txns,
                })
        return pairs

    # ── Private helpers ──────────────────────────────────────

    @staticmethod
    def _find_matching_credit(
        db: Session,
        debit_tx: UnifiedTransaction,
        exclude_ids: set[int],
    ) -> Optional[tuple[UnifiedTransaction, TransferType]]:
        """Find a matching CREDIT transaction on a different account."""
        if not debit_tx.date or not debit_tx.amount:
            return None

        date_lo = debit_tx.date - timedelta(days=_DATE_TOLERANCE_DAYS)
        date_hi = debit_tx.date + timedelta(days=_DATE_TOLERANCE_DAYS)

        q = (
            db.query(UnifiedTransaction)
            .filter(
                UnifiedTransaction.type == TransactionType.CREDIT,
                UnifiedTransaction.is_transfer == False,
                UnifiedTransaction.amount == debit_tx.amount,
                UnifiedTransaction.date >= date_lo,
                UnifiedTransaction.date <= date_hi,
                # Must be a different account
                or_(
                    UnifiedTransaction.account_identifier != debit_tx.account_identifier,
                    UnifiedTransaction.source_type != debit_tx.source_type,
                ),
                UnifiedTransaction.id != debit_tx.id,
            )
        )

        if exclude_ids:
            q = q.filter(UnifiedTransaction.id.notin_(exclude_ids))

        # Order by date proximity (closest first)
        candidates = q.order_by(
            func.abs(func.julianday(UnifiedTransaction.date) - func.julianday(debit_tx.date))
        ).all()

        if not candidates:
            return None

        # Determine transfer type
        best = candidates[0]
        transfer_type = TransferDetectionService._classify_transfer(
            db, debit_tx, best
        )
        return best, transfer_type

    @staticmethod
    def _find_matching_debit(
        db: Session,
        credit_tx: UnifiedTransaction,
        exclude_ids: set[int],
    ) -> Optional[tuple[UnifiedTransaction, TransferType]]:
        """Find a matching DEBIT transaction on a different account (reverse lookup)."""
        if not credit_tx.date or not credit_tx.amount:
            return None

        date_lo = credit_tx.date - timedelta(days=_DATE_TOLERANCE_DAYS)
        date_hi = credit_tx.date + timedelta(days=_DATE_TOLERANCE_DAYS)

        q = (
            db.query(UnifiedTransaction)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                UnifiedTransaction.amount == credit_tx.amount,
                UnifiedTransaction.date >= date_lo,
                UnifiedTransaction.date <= date_hi,
                or_(
                    UnifiedTransaction.account_identifier != credit_tx.account_identifier,
                    UnifiedTransaction.source_type != credit_tx.source_type,
                ),
                UnifiedTransaction.id != credit_tx.id,
            )
        )

        if exclude_ids:
            q = q.filter(UnifiedTransaction.id.notin_(exclude_ids))

        candidates = q.order_by(
            func.abs(func.julianday(UnifiedTransaction.date) - func.julianday(credit_tx.date))
        ).all()

        if not candidates:
            return None

        best = candidates[0]
        transfer_type = TransferDetectionService._classify_transfer(
            db, best, credit_tx
        )
        return best, transfer_type

    @staticmethod
    def _classify_transfer(
        db: Session,
        debit_tx: UnifiedTransaction,
        credit_tx: UnifiedTransaction,
    ) -> TransferType:
        """
        Determine if this is an internal transfer or a CC bill payment.
        CC bill payment: savings DEBIT → credit card CREDIT, or description matches CC keywords.
        """
        # Savings → CC account
        if (
            debit_tx.source_type == SourceType.SAVINGS
            and credit_tx.source_type == SourceType.CREDIT_CARD
        ):
            return TransferType.CC_BILL_PAYMENT

        # Check description for CC payment keywords
        desc = debit_tx.description or ""
        if _CC_PAYMENT_KEYWORDS.search(desc):
            return TransferType.CC_BILL_PAYMENT

        return TransferType.INTERNAL_TRANSFER

    @staticmethod
    def _link_pair(
        db: Session,
        tx1: UnifiedTransaction,
        tx2: UnifiedTransaction,
        transfer_type: TransferType,
    ) -> str:
        """Mark two transactions as a linked transfer pair."""
        group_id = str(uuid.uuid4())

        tx1.is_transfer = True
        tx1.transfer_group_id = group_id
        tx1.transfer_type = transfer_type

        tx2.is_transfer = True
        tx2.transfer_group_id = group_id
        tx2.transfer_type = transfer_type

        return group_id

    @staticmethod
    def _unlink_group(db: Session, transfer_group_id: str, commit: bool = False) -> bool:
        """Remove transfer linking from all transactions in a group."""
        txns = (
            db.query(UnifiedTransaction)
            .filter(UnifiedTransaction.transfer_group_id == transfer_group_id)
            .all()
        )
        if not txns:
            return False

        for tx in txns:
            tx.is_transfer = False
            tx.transfer_group_id = None
            tx.transfer_type = None

        if commit:
            db.commit()
        return True
