"""
Accounts & Statement Management service.

Provides:
  - Account listing, creation, update, merge, soft-delete
  - Per-account summary (balance, transaction/statement counts)
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
    def create_account(db: Session, **kwargs) -> BankAccount:
        account = BankAccount(**kwargs)
        db.add(account)
        db.commit()
        db.refresh(account)
        return account

    @staticmethod
    def update_account(db: Session, account_id: int, **kwargs) -> BankAccount | None:
        account = db.query(BankAccount).filter(BankAccount.id == account_id).first()
        if not account:
            return None
        for key, value in kwargs.items():
            if value is not None:
                setattr(account, key, value)
        db.commit()
        db.refresh(account)
        return account

    @staticmethod
    def merge_accounts(db: Session, source_id: int, target_id: int) -> dict:
        source_account = db.query(BankAccount).filter(BankAccount.id == source_id).first()
        target_account = db.query(BankAccount).filter(BankAccount.id == target_id).first()
        
        if not source_account or not target_account:
            raise ValueError("Source or target account not found")

        tx_count = db.query(UnifiedTransaction).filter(UnifiedTransaction.bank_account_id == source_id).update({"bank_account_id": target_id})
        stmt_count = db.query(StatementAudit).filter(StatementAudit.bank_account_id == source_id).update({"bank_account_id": target_id})
        
        source_account.is_active = False
        db.commit()
        
        logger.info(f"Merged account {source_id} into {target_id}. Reassigned {tx_count} txns and {stmt_count} stmts.")
        return {"reassigned_transactions": tx_count, "reassigned_statements": stmt_count}

    @staticmethod
    def delete_account(db: Session, account_id: int) -> bool:
        account = db.query(BankAccount).filter(BankAccount.id == account_id).first()
        if not account:
            return False
            
        account.is_active = False
        db.commit()
        logger.info(f"Soft-deleted account {account_id}")
        return True

    @staticmethod
    def get_account_summary(db: Session, account_id: int) -> dict | None:
        ba = db.query(BankAccount).filter(BankAccount.id == account_id).first()
        if not ba:
            return None

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

        tx_count = (
            db.query(func.count(UnifiedTransaction.id))
            .filter(UnifiedTransaction.bank_account_id == ba.id)
            .scalar()
        ) or 0

        latest_audit = (
            db.query(StatementAudit)
            .filter(
                StatementAudit.bank_account_id == ba.id,
                StatementAudit.status == "SUCCESS",
            )
            .order_by(StatementAudit.period_end.desc())
            .first()
        )
        
        history_audits = (
            db.query(StatementAudit)
            .filter(StatementAudit.bank_account_id == ba.id, StatementAudit.status == "SUCCESS")
            .order_by(StatementAudit.period_end.desc())
            .all()
        )
        balance_history = [
            {
                "period_end": a.period_end.isoformat() if a.period_end else None,
                "closing_balance": float(a.closing_balance) if a.closing_balance else None
            }
            for a in history_audits if a.closing_balance is not None
        ]

        entry = {
            "id": ba.id,
            "type": ba.account_type,
            "identifier": ba.account_number,
            "name": ba.name,
            "holder_name": ba.holder_name,
            "bank": ba.bank_name,
            "account_subtype": ba.account_subtype,
            "notes": ba.notes,
            "is_active": ba.is_active,
            "created_at": ba.created_at.isoformat() if ba.created_at else None,
            "loan_principal": float(ba.loan_principal) if ba.loan_principal else None,
            "loan_interest_rate": float(ba.loan_interest_rate) if ba.loan_interest_rate else None,
            "loan_emi_amount": float(ba.loan_emi_amount) if ba.loan_emi_amount else None,
            "loan_start_date": ba.loan_start_date.isoformat() if ba.loan_start_date else None,
            "loan_end_date": ba.loan_end_date.isoformat() if ba.loan_end_date else None,
            "credit_limit": float(ba.credit_limit) if ba.credit_limit else None,
            "billing_cycle_day": ba.billing_cycle_day,
            "invested_amount": float(ba.invested_amount) if ba.invested_amount else None,
            "current_value": float(ba.current_value) if ba.current_value else None,
            "value_updated_at": ba.value_updated_at.isoformat() if ba.value_updated_at else None,
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
            "balance_history": balance_history,
        }
        return entry


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
