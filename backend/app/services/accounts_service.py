"""
Accounts & Statement Management service.

Provides:
  - Account discovery (distinct accounts/cards from uploaded statements)
  - Statement listing, detail, deletion
  - Cascading delete of unified transactions when source statements are removed
"""
import logging
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy import func, distinct, or_
from sqlalchemy.orm import Session

from app.models.credit_card import CreditCardStatement, CreditCardTransaction
from app.models.savings_account import SavingsAccountStatement, SavingsAccountTransaction
from app.models.transaction import UnifiedTransaction
from app.models.enums import SourceType

logger = logging.getLogger(__name__)


class AccountsService:
    """Discover linked accounts/cards from uploaded statement data."""

    @staticmethod
    def get_accounts(db: Session) -> list[dict]:
        """
        Return all known accounts/cards with summary info.
        Each entry: {type, identifier, bank, holder_name, statement_count,
                     transaction_count, last_statement_date, balance}
        """
        accounts: list[dict] = []

        # ── Savings accounts ─────────────────────────────
        savings_rows = (
            db.query(
                SavingsAccountStatement.account_number,
                SavingsAccountStatement.account_holder_name,
                func.count(SavingsAccountStatement.id).label("stmt_count"),
                func.max(SavingsAccountStatement.to_date).label("last_date"),
            )
            .group_by(
                SavingsAccountStatement.account_number,
                SavingsAccountStatement.account_holder_name,
            )
            .all()
        )

        for row in savings_rows:
            # Latest closing balance
            latest = (
                db.query(SavingsAccountStatement)
                .filter(SavingsAccountStatement.account_number == row.account_number)
                .order_by(SavingsAccountStatement.to_date.desc())
                .first()
            )
            tx_count = (
                db.query(func.count(SavingsAccountTransaction.id))
                .join(SavingsAccountStatement)
                .filter(SavingsAccountStatement.account_number == row.account_number)
                .scalar()
            )

            # Try to get bank from unified transactions
            bank = (
                db.query(UnifiedTransaction.bank)
                .filter(
                    UnifiedTransaction.source_type == SourceType.SAVINGS,
                    UnifiedTransaction.account_identifier == row.account_number,
                    UnifiedTransaction.bank.isnot(None),
                )
                .first()
            )

            accounts.append({
                "type": "SAVINGS",
                "identifier": row.account_number,
                "holder_name": row.account_holder_name,
                "bank": bank[0] if bank else None,
                "statement_count": row.stmt_count,
                "transaction_count": tx_count or 0,
                "last_statement_date": row.last_date.isoformat() if row.last_date else None,
                "balance": float(latest.closing_balance) if latest and latest.closing_balance else None,
            })

        # ── Credit cards ─────────────────────────────────
        cc_rows = (
            db.query(
                CreditCardStatement.card_number,
                CreditCardStatement.card_holder_name,
                func.count(CreditCardStatement.id).label("stmt_count"),
                func.max(CreditCardStatement.statement_date).label("last_date"),
            )
            .group_by(
                CreditCardStatement.card_number,
                CreditCardStatement.card_holder_name,
            )
            .all()
        )

        for row in cc_rows:
            latest = (
                db.query(CreditCardStatement)
                .filter(CreditCardStatement.card_number == row.card_number)
                .order_by(CreditCardStatement.statement_date.desc())
                .first()
            )
            tx_count = (
                db.query(func.count(CreditCardTransaction.id))
                .join(CreditCardStatement)
                .filter(CreditCardStatement.card_number == row.card_number)
                .scalar()
            )

            bank = (
                db.query(UnifiedTransaction.bank)
                .filter(
                    UnifiedTransaction.source_type == SourceType.CREDIT_CARD,
                    UnifiedTransaction.account_identifier == row.card_number,
                    UnifiedTransaction.bank.isnot(None),
                )
                .first()
            )

            accounts.append({
                "type": "CREDIT_CARD",
                "identifier": row.card_number,
                "holder_name": row.card_holder_name,
                "bank": bank[0] if bank else None,
                "statement_count": row.stmt_count,
                "transaction_count": tx_count or 0,
                "last_statement_date": row.last_date.isoformat() if row.last_date else None,
                "balance": float(latest.total_dues) if latest and latest.total_dues else None,
                "credit_limit": float(latest.credit_limit) if latest and latest.credit_limit else None,
                "available_credit": float(latest.available_credit) if latest and latest.available_credit else None,
            })

        return accounts


    @staticmethod
    def rename_account(
        db: Session,
        account_type: str,
        identifier: str,
        new_name: str,
    ) -> bool:
        """
        Update the holder name across all statements for a given account.
        Returns True if at least one statement was updated.
        """
        if account_type == "SAVINGS":
            count = (
                db.query(SavingsAccountStatement)
                .filter(SavingsAccountStatement.account_number == identifier)
                .update({SavingsAccountStatement.account_holder_name: new_name})
            )
        elif account_type == "CREDIT_CARD":
            count = (
                db.query(CreditCardStatement)
                .filter(CreditCardStatement.card_number == identifier)
                .update({CreditCardStatement.card_holder_name: new_name})
            )
        else:
            return False

        if count > 0:
            db.commit()
            logger.info(
                f"Renamed {account_type} account {identifier} to '{new_name}' "
                f"({count} statements updated)"
            )
        return count > 0


class StatementManagementService:
    """CRUD operations for statements."""

    # ── List statements ──────────────────────────────────

    @staticmethod
    def list_savings_statements(
        db: Session,
        *,
        account_number: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[SavingsAccountStatement], int]:
        q = db.query(SavingsAccountStatement)
        if account_number:
            q = q.filter(SavingsAccountStatement.account_number == account_number)
        total = q.count()
        items = q.order_by(SavingsAccountStatement.to_date.desc()).offset(offset).limit(limit).all()
        return items, total

    @staticmethod
    def list_cc_statements(
        db: Session,
        *,
        card_number: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[CreditCardStatement], int]:
        q = db.query(CreditCardStatement)
        if card_number:
            q = q.filter(CreditCardStatement.card_number == card_number)
        total = q.count()
        items = q.order_by(CreditCardStatement.statement_date.desc()).offset(offset).limit(limit).all()
        return items, total

    # ── Delete statement ─────────────────────────────────

    @staticmethod
    def delete_savings_statement(db: Session, statement_id: int) -> bool:
        """
        Delete a savings statement and cascade-remove its unified transactions.
        Returns True if deleted, False if not found.
        """
        stmt = db.query(SavingsAccountStatement).filter(
            SavingsAccountStatement.id == statement_id
        ).first()
        if not stmt:
            return False

        # Remove related unified transactions
        tx_ids = [tx.id for tx in stmt.transactions]
        if tx_ids:
            db.query(UnifiedTransaction).filter(
                UnifiedTransaction.source_type == SourceType.SAVINGS,
                UnifiedTransaction.source_transaction_id.in_(tx_ids),
            ).delete(synchronize_session="fetch")

        db.delete(stmt)
        db.commit()
        logger.info(f"Deleted savings statement id={statement_id} ({len(tx_ids)} unified txns removed)")
        return True

    @staticmethod
    def delete_cc_statement(db: Session, statement_id: int) -> bool:
        """
        Delete a credit card statement and cascade-remove its unified transactions.
        """
        stmt = db.query(CreditCardStatement).filter(
            CreditCardStatement.id == statement_id
        ).first()
        if not stmt:
            return False

        tx_ids = [tx.id for tx in stmt.transactions]
        if tx_ids:
            db.query(UnifiedTransaction).filter(
                UnifiedTransaction.source_type == SourceType.CREDIT_CARD,
                UnifiedTransaction.source_transaction_id.in_(tx_ids),
            ).delete(synchronize_session="fetch")

        db.delete(stmt)
        db.commit()
        logger.info(f"Deleted CC statement id={statement_id} ({len(tx_ids)} unified txns removed)")
        return True

    # ── Delete individual unified transaction ────────────

    @staticmethod
    def delete_unified_transaction(db: Session, transaction_id: int) -> bool:
        """Delete a single unified transaction."""
        tx = db.query(UnifiedTransaction).filter(
            UnifiedTransaction.id == transaction_id
        ).first()
        if not tx:
            return False
        db.delete(tx)
        db.commit()
        logger.info(f"Deleted unified transaction id={transaction_id}")
        return True
