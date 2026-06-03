"""
Accounts & Statement Management service.

Provides:
  - Account listing from bank_accounts table
  - Statement listing from statement_audit table
  - Statement & transaction deletion with cascade
"""
import logging
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.bank_account import BankAccount
from app.models.statement_audit import StatementAudit
from app.models.transaction import UnifiedTransaction

logger = logging.getLogger(__name__)


class AccountsService:
    """Query linked accounts from the bank_accounts table."""

    @staticmethod
    def get_accounts(db: Session) -> list[dict]:
        """
        Return all known accounts with summary info from bank_accounts,
        statement_audit, and unified_transactions.
        """
        accounts: list[dict] = []

        bank_accounts = db.query(BankAccount).filter(BankAccount.is_active == True).all()

        for ba in bank_accounts:
            # Statement count + latest period end
            stmt_agg = (
                db.query(
                    func.count(StatementAudit.id).label("stmt_count"),
                    func.max(StatementAudit.period_end).label("last_date"),
                )
                .filter(
                    StatementAudit.bank_account_id == ba.id,
                    StatementAudit.status == "SUCCESS",
                )
                .first()
            )

            # Transaction count
            tx_count = (
                db.query(func.count(UnifiedTransaction.id))
                .filter(UnifiedTransaction.bank_account_id == ba.id)
                .scalar()
            ) or 0

            # Latest closing balance from the most recent audit
            latest_audit = (
                db.query(StatementAudit)
                .filter(
                    StatementAudit.bank_account_id == ba.id,
                    StatementAudit.status == "SUCCESS",
                )
                .order_by(StatementAudit.period_end.desc())
                .first()
            )

            entry = {
                "id": ba.id,
                "type": ba.account_type,
                "identifier": ba.account_number,
                "name": ba.name,
                "holder_name": ba.holder_name,
                "bank": ba.bank_name,
                "statement_count": stmt_agg.stmt_count if stmt_agg else 0,
                "transaction_count": tx_count,
                "last_statement_date": (
                    stmt_agg.last_date.isoformat()
                    if stmt_agg and stmt_agg.last_date
                    else None
                ),
                "balance": (
                    float(latest_audit.closing_balance)
                    if latest_audit and latest_audit.closing_balance
                    else None
                ),
            }

            # CC-specific fields
            if ba.account_type == "CREDIT_CARD" and latest_audit:
                entry["credit_limit"] = (
                    float(latest_audit.credit_limit)
                    if latest_audit.credit_limit else None
                )
                entry["available_credit"] = (
                    float(latest_audit.available_credit)
                    if latest_audit.available_credit else None
                )

            accounts.append(entry)

        return accounts

    @staticmethod
    def rename_account(
        db: Session,
        account_type: str,
        identifier: str,
        new_name: str,
    ) -> bool:
        """
        Update the holder name on a bank account.
        Returns True if the account was found and updated.
        """
        ba = (
            db.query(BankAccount)
            .filter(
                BankAccount.account_type == account_type,
                BankAccount.account_number == identifier,
            )
            .first()
        )
        if not ba:
            return False

        ba.holder_name = new_name
        ba.name = new_name  # also update the display name
        db.commit()
        logger.info(f"Renamed {account_type} account {identifier} to '{new_name}'")
        return True


class StatementManagementService:
    """CRUD operations for statements (via statement_audit)."""

    # ── List statements ──────────────────────────────────

    @staticmethod
    def list_statements(
        db: Session,
        *,
        statement_type: str | None = None,
        bank_account_id: int | None = None,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[StatementAudit], int]:
        """List statement audits, defaulting to successful imports only."""
        q = db.query(StatementAudit)
        if status:
            q = q.filter(StatementAudit.status == status)
        else:
            q = q.filter(StatementAudit.status == "SUCCESS")
        if statement_type:
            q = q.filter(StatementAudit.statement_type == statement_type)
        if bank_account_id:
            q = q.filter(StatementAudit.bank_account_id == bank_account_id)
        total = q.count()
        items = q.order_by(StatementAudit.period_end.desc()).offset(offset).limit(limit).all()
        return items, total

    # ── Delete statement ─────────────────────────────────

    @staticmethod
    def delete_statement(db: Session, audit_id: int) -> bool:
        """
        Delete a statement audit and cascade-remove its unified transactions.
        Returns True if deleted, False if not found.
        """
        audit = db.query(StatementAudit).filter(
            StatementAudit.id == audit_id
        ).first()
        if not audit:
            return False

        # Remove linked unified transactions
        deleted_count = (
            db.query(UnifiedTransaction)
            .filter(UnifiedTransaction.statement_audit_id == audit_id)
            .delete(synchronize_session="fetch")
        )

        db.delete(audit)
        db.commit()
        logger.info(
            f"Deleted statement audit id={audit_id} "
            f"({deleted_count} unified txns removed)"
        )
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
