"""
BankAccount model — first-class entity for bank accounts and credit cards.

Replaces the scattered account_number / card_number / bank strings that were
previously stored directly on statements and unified transactions.
"""
from datetime import datetime

from sqlalchemy import String, Boolean, DateTime, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


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

    def __repr__(self) -> str:
        return (
            f"<BankAccount(id={self.id}, name={self.name!r}, "
            f"bank={self.bank_name}, type={self.account_type}, "
            f"acct={self.account_number})>"
        )
