"""
UPI ID model — maps UPI handles to accounts and/or categories.

Two use cases:
  1. Own UPI IDs (is_own=True): linked to a user's bank account,
     used to auto-flag transactions as transfers.
  2. Third-party UPI IDs (is_own=False): mapped to a category,
     used to auto-categorize transactions by UPI handle.
"""
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UpiId(Base):
    __tablename__ = "upi_ids"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    upi_handle: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True,
    )
    label: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)

    # Link to a user's own account (nullable for third-party UPIs)
    account_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    account_identifier: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)

    # Auto-categorization target (nullable — not every UPI needs a category)
    category_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("categories.id"), nullable=True,
    )

    is_own: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="0", nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False,
    )

    # Relationships
    category: Mapped[Optional["Category"]] = relationship(lazy="selectin")  # noqa: F821

    def __repr__(self) -> str:
        return (
            f"<UpiId(id={self.id}, handle={self.upi_handle}, "
            f"is_own={self.is_own}, category_id={self.category_id})>"
        )
