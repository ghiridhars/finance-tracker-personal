"""ClassificationRule — user-defined rules that auto-classify transactions across all accounts."""
from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class ClassificationRule(Base):
    __tablename__ = "classification_rules"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    
    # Match criteria (any combination — all non-null criteria must match)
    pattern: Mapped[str | None] = mapped_column(String(500), nullable=True)  # Substring or regex on description
    pattern_is_regex: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0", nullable=False)
    upi_handle: Mapped[str | None] = mapped_column(String(100), nullable=True)  # Exact UPI handle
    amount_min: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    amount_max: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    bank_filter: Mapped[str | None] = mapped_column(String(30), nullable=True)  # Specific bank, NULL = all
    transaction_type_filter: Mapped[str | None] = mapped_column(String(10), nullable=True)  # CREDIT or DEBIT, NULL = both
    
    # Action — what to set on matching transactions
    target_category_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    target_merchant: Mapped[str | None] = mapped_column(String(200), nullable=True)
    mark_as_transfer: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0", nullable=False)
    mark_as_excluded: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0", nullable=False)
    
    # Meta
    priority: Mapped[int] = mapped_column(Integer, default=100, server_default="100", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1", nullable=False)
    applied_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    target_category: Mapped[Optional["Category"]] = relationship(lazy="selectin")
    
    def __repr__(self) -> str:
        return f"<ClassificationRule(id={self.id}, name={self.name!r}, pattern={self.pattern!r})>"
