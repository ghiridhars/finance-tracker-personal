"""
Credit Card SQLAlchemy models.
Replaces:
  - app.personal.model.CreditCardStatement (JPA @Entity)
  - app.personal.model.CreditCardTransaction (JPA @Entity)

FIX: Added UniqueConstraint on (card_number, statement_date) to prevent duplicates.
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


class CreditCardStatement(Base):
    """
    Replaces: CreditCardStatement.java (JPA @Entity)
    Table: credit_card_statements
    """
    __tablename__ = "credit_card_statements"

    # FIX: unique constraint on card_number + statement_date
    __table_args__ = (
        UniqueConstraint("card_number", "statement_date", name="uq_cc_card_date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    statement_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    card_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
    card_holder_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    credit_limit: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    available_credit: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    total_dues: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    minimum_amount_due: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)

    # Replaces: @OneToMany(mappedBy="statement", cascade=ALL, orphanRemoval=true)
    transactions: Mapped[List["CreditCardTransaction"]] = relationship(
        back_populates="statement",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<CreditCardStatement(id={self.id}, card={self.card_number}, date={self.statement_date})>"


class CreditCardTransaction(Base):
    """
    Replaces: CreditCardTransaction.java (JPA @Entity)
    Table: credit_card_transactions
    """
    __tablename__ = "credit_card_transactions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    date: Mapped[date | None] = mapped_column(Date, nullable=True)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    amount: Mapped[Decimal | None] = mapped_column(Numeric(15, 2), nullable=True)
    type: Mapped[str | None] = mapped_column(SAEnum(TransactionType), nullable=True)
    reference_number: Mapped[str | None] = mapped_column(String(100), nullable=True)

    # Replaces: @ManyToOne(fetch=LAZY) @JoinColumn(name="statement_id")
    statement_id: Mapped[int | None] = mapped_column(ForeignKey("credit_card_statements.id"), nullable=True)
    statement: Mapped["CreditCardStatement | None"] = relationship(back_populates="transactions")

    def __repr__(self) -> str:
        return f"<CreditCardTransaction(id={self.id}, date={self.date}, amount={self.amount})>"
