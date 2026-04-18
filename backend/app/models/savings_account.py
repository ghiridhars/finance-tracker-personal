"""
Savings Account SQLAlchemy models.
Replaces:
  - app.personal.model.SavingsAccountStatement (JPA @Entity)
  - app.personal.model.SavingsAccountTransaction (JPA @Entity)

FIX: Added UniqueConstraint on (account_number, from_date, to_date) to prevent duplicates.
     Original Java version had no unique constraints.
"""
from datetime import date
from decimal import Decimal
from typing import List

from sqlalchemy import (
    String, Date, Numeric, ForeignKey, UniqueConstraint, Enum as SAEnum
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TransactionType


class SavingsAccountStatement(Base):
    """
    Replaces: SavingsAccountStatement.java (JPA @Entity)
    Table: savings_account_statements
    """
    __tablename__ = "savings_account_statements"

    # FIX: unique constraint on account_number + date range
    __table_args__ = (
        UniqueConstraint("account_number", "from_date", "to_date", name="uq_sa_acct_dates"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    bank_account_id: Mapped[int | None] = mapped_column(
        ForeignKey("bank_accounts.id"), nullable=True
    )
    account_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
    account_holder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ifsc_code: Mapped[str | None] = mapped_column(String(11), nullable=True)
    branch_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    from_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    to_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    opening_balance: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    closing_balance: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)

    # Replaces: @OneToMany(mappedBy="statement", cascade=ALL, orphanRemoval=true)
    transactions: Mapped[List["SavingsAccountTransaction"]] = relationship(
        back_populates="statement",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<SavingsAccountStatement(id={self.id}, acct={self.account_number})>"


class SavingsAccountTransaction(Base):
    """
    Replaces: SavingsAccountTransaction.java (JPA @Entity)
    Table: savings_account_transactions
    """
    __tablename__ = "savings_account_transactions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    date: Mapped[date | None] = mapped_column(Date, nullable=True)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    reference_number: Mapped[str | None] = mapped_column(String(100), nullable=True)
    withdrawal_amount: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    deposit_amount: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    closing_balance: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    type: Mapped[str | None] = mapped_column(SAEnum(TransactionType), nullable=True)

    # Replaces: @ManyToOne(fetch=LAZY) @JoinColumn(name="statement_id")
    statement_id: Mapped[int | None] = mapped_column(ForeignKey("savings_account_statements.id"), nullable=True)
    statement: Mapped["SavingsAccountStatement | None"] = relationship(back_populates="transactions")

    def __repr__(self) -> str:
        return f"<SavingsAccountTransaction(id={self.id}, date={self.date})>"
