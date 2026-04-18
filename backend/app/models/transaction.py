"""
UnifiedTransaction — single denormalized table that normalizes
credit card and savings account transactions into one queryable model.

Populated automatically when statements are saved.
"""
from datetime import date as date_type, datetime
from decimal import Decimal
from typing import List, Optional

from sqlalchemy import (
    Boolean, String, Date, DateTime, Numeric, Integer, Text,
    ForeignKey, Enum as SAEnum,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TransactionType, SourceType, BankType, TransferType, ReviewStatus
from app.models.category import Category
from app.models.tag import Tag, TransactionTag


class UnifiedTransaction(Base):
    """
    A single row per financial transaction, regardless of source
    (savings deposit, credit card charge, etc.).

    Fields:
        amount  — always positive; direction indicated by `type`.
        type    — CREDIT (money in) or DEBIT (money out).
        source_type / source_transaction_id — FK back to the original table.
    """
    __tablename__ = "unified_transactions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    date: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(15, 2), nullable=True)
    type: Mapped[Optional[str]] = mapped_column(SAEnum(TransactionType), nullable=True)

    # Source tracing
    source_type: Mapped[str] = mapped_column(SAEnum(SourceType), nullable=False)
    statement_audit_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("statement_audit.id"), nullable=True
    )

    # Bank & account
    bank: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    account_identifier: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    bank_account_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("bank_accounts.id"), nullable=True
    )

    # Categorization
    category_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("categories.id"), nullable=True
    )
    merchant_name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)

    # User annotations
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    reference_number: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # Transfer linking
    is_transfer: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0", nullable=False)
    transfer_group_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True, index=True)
    transfer_type: Mapped[Optional[str]] = mapped_column(SAEnum(TransferType), nullable=True)

    # Parse confidence
    review_status: Mapped[Optional[str]] = mapped_column(
        String(20), default=ReviewStatus.AUTO_PARSED.value, nullable=True
    )

    # Audit
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )

    # Relationships
    category: Mapped[Optional["Category"]] = relationship(lazy="selectin")
    tags: Mapped[List["Tag"]] = relationship(
        secondary="transaction_tags", lazy="selectin"
    )

    def __repr__(self) -> str:
        return (
            f"<UnifiedTransaction(id={self.id}, date={self.date}, "
            f"amount={self.amount}, type={self.type}, source={self.source_type})>"
        )
