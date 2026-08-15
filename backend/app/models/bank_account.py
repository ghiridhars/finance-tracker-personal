"""
BankAccount model — first-class entity for bank accounts and credit cards.

Replaces the scattered account_number / card_number / bank strings that were
previously stored directly on statements and unified transactions.
"""
from datetime import date as date_type, datetime
from decimal import Decimal
from typing import TYPE_CHECKING, List

from sqlalchemy import String, Boolean, DateTime, Date, Integer, Numeric, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

if TYPE_CHECKING:
    from app.models.transaction import UnifiedTransaction
    from app.models.statement_audit import StatementAudit


class BankAccount(Base):
    """
    A known bank account or credit card.

    Auto-created on first statement import; editable by the user afterward.
    """
    __tablename__ = "bank_accounts"
    __table_args__ = (
        UniqueConstraint(
            "bank_name", "account_type", "account_number",
            name="uq_bank_acct_type_num",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    bank_name: Mapped[str] = mapped_column(String(30), nullable=False)
    account_type: Mapped[str] = mapped_column(String(20), nullable=False)  # SAVINGS / CREDIT_CARD
    account_number: Mapped[str | None] = mapped_column(String(30), nullable=True)
    holder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ifsc_code: Mapped[str | None] = mapped_column(String(11), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1", nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    
    account_subtype: Mapped[str | None] = mapped_column(String(30), nullable=True)  # SAVINGS, SALARY, LOAN_HOME, LOAN_PERSONAL, FD, MF, DEMAT, PPF, NPS, etc.
    loan_principal: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    loan_interest_rate: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    loan_emi_amount: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    loan_start_date: Mapped[date_type | None] = mapped_column(Date, nullable=True)
    loan_end_date: Mapped[date_type | None] = mapped_column(Date, nullable=True)
    credit_limit: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    billing_cycle_day: Mapped[int | None] = mapped_column(Integer, nullable=True)
    invested_amount: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    current_value: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    value_updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── Relationships ────────────────────────────────────
    transactions: Mapped[List["UnifiedTransaction"]] = relationship(
        "UnifiedTransaction",
        foreign_keys="UnifiedTransaction.bank_account_id",
        back_populates="bank_account",
        lazy="dynamic",
    )
    # Inverse references for transfers — money leaves this account (debit origin)
    from_transactions: Mapped[List["UnifiedTransaction"]] = relationship(
        "UnifiedTransaction",
        foreign_keys="UnifiedTransaction.from_account_id",
        lazy="dynamic",
        overlaps="from_account",
    )
    # Inverse references for transfers — money arrives into this account (credit destination)
    to_transactions: Mapped[List["UnifiedTransaction"]] = relationship(
        "UnifiedTransaction",
        foreign_keys="UnifiedTransaction.to_account_id",
        lazy="dynamic",
        overlaps="to_account",
    )
    statement_audits: Mapped[List["StatementAudit"]] = relationship(
        "StatementAudit",
        foreign_keys="StatementAudit.bank_account_id",
        back_populates="bank_account",
        lazy="dynamic",
    )

    def __repr__(self) -> str:
        return (
            f"<BankAccount(id={self.id}, name={self.name!r}, "
            f"bank={self.bank_name}, type={self.account_type}, "
            f"acct={self.account_number})>"
        )
