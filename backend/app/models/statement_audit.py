"""
StatementAudit model — tracks every parse attempt AND stores statement-level
metadata (replaces the old credit_card_statements / savings_account_statements tables).
"""
from datetime import date as date_type, datetime
from decimal import Decimal
from typing import TYPE_CHECKING, Optional

from sqlalchemy import String, Integer, Text, DateTime, Date, Numeric, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

if TYPE_CHECKING:
    from app.models.bank_account import BankAccount


class StatementAudit(Base):
    """
    One row per parse attempt.  For successful imports this also holds the
    statement-level header data (balances, dates, limits) that used to live
    in the separate credit_card_statements / savings_account_statements tables.
    """
    __tablename__ = "statement_audit"
    __table_args__ = (
        UniqueConstraint(
            "bank_account_id", "period_start", "period_end",
            name="uq_audit_acct_period",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    file_name: Mapped[str] = mapped_column(String(500), nullable=False)
    file_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    file_size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Account linkage (nullable for failed imports where account isn't resolved)
    bank_account_id: Mapped[int | None] = mapped_column(
        ForeignKey("bank_accounts.id"), nullable=True
    )
    bank_account: Mapped[Optional["BankAccount"]] = relationship(
        "BankAccount", foreign_keys=[bank_account_id],
        back_populates="statement_audits", lazy="selectin"
    )
    # Denormalized bank name for failed imports where account doesn't exist yet
    bank_name: Mapped[str | None] = mapped_column(String(30), nullable=True)
    statement_type: Mapped[str] = mapped_column(String(20), nullable=False)

    # ── Statement period & balances ─────────────────────
    period_start: Mapped[date_type | None] = mapped_column(Date, nullable=True)
    period_end: Mapped[date_type | None] = mapped_column(Date, nullable=True)
    opening_balance: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    closing_balance: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)

    # ── Credit-card-specific metadata ───────────────────
    due_date: Mapped[date_type | None] = mapped_column(Date, nullable=True)
    credit_limit: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    available_credit: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    minimum_amount_due: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)

    # ── Savings-specific metadata ───────────────────────
    account_holder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    card_holder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    account_number: Mapped[str | None] = mapped_column(String(30), nullable=True)
    card_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
    ifsc_code: Mapped[str | None] = mapped_column(String(11), nullable=True)
    branch_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # ── Parsing details ─────────────────────────────────
    parser_strategy: Mapped[str | None] = mapped_column(String(50), nullable=True)
    transaction_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    status: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    parse_trace: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Import source and timestamp
    source: Mapped[str] = mapped_column(String(20), nullable=False)  # upload / local_sync / gdrive
    imported_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )

    def __repr__(self) -> str:
        return (
            f"<StatementAudit(id={self.id}, file={self.file_name!r}, "
            f"status={self.status}, txns={self.transaction_count})>"
        )
