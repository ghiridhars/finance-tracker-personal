"""
Phase 5 models — Budget, SavingsGoal, BillReminder, RecurringTransaction.
"""
from datetime import date as date_type, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    String, Date, DateTime, Numeric, Integer, Text, Boolean,
    ForeignKey, Enum as SAEnum, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.category import Category


# ──────────────────────────────────────────────────────────────
# Budget — monthly spending limit per category
# ──────────────────────────────────────────────────────────────

class Budget(Base):
    """
    Monthly budget for a category.
    year + month + category_id is unique — one budget per category per month.
    If `rollover` is True, unspent amount carries over to next month.
    """
    __tablename__ = "budgets"
    __table_args__ = (
        UniqueConstraint("year", "month", "category_id", name="uq_budget_year_month_cat"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=False)
    year: Mapped[int] = mapped_column(Integer, nullable=False)
    month: Mapped[int] = mapped_column(Integer, nullable=False)  # 1-12
    amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
    rollover: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationships
    category: Mapped["Category"] = relationship(lazy="selectin")

    def __repr__(self) -> str:
        return f"<Budget(id={self.id}, {self.year}-{self.month:02d}, cat={self.category_id}, amount={self.amount})>"


# ──────────────────────────────────────────────────────────────
# SavingsGoal — track progress toward a savings target
# ──────────────────────────────────────────────────────────────

class SavingsGoal(Base):
    """
    A user-defined savings goal (e.g. Emergency Fund, Vacation).
    `current_amount` is updated manually or via contributions.
    """
    __tablename__ = "savings_goals"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    target_amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
    current_amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), default=0)
    deadline: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True)
    icon: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    color: Mapped[Optional[str]] = mapped_column(String(7), nullable=True)  # hex
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    def __repr__(self) -> str:
        return f"<SavingsGoal(id={self.id}, name='{self.name}', {self.current_amount}/{self.target_amount})>"


# ──────────────────────────────────────────────────────────────
# BillReminder — upcoming payments / due dates
# ──────────────────────────────────────────────────────────────

class BillReminder(Base):
    """
    A recurring bill or one-time payment reminder.
    `day_of_month` for recurring, `next_due_date` computed or manual.
    """
    __tablename__ = "bill_reminders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(15, 2), nullable=True)
    category_id: Mapped[Optional[int]] = mapped_column(ForeignKey("categories.id"), nullable=True)
    is_recurring: Mapped[bool] = mapped_column(Boolean, default=True)
    frequency: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)  # MONTHLY, QUARTERLY, YEARLY
    day_of_month: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # 1-31
    next_due_date: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True)
    is_auto_detected: Mapped[bool] = mapped_column(Boolean, default=False)
    is_paid: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationships
    category: Mapped[Optional["Category"]] = relationship(lazy="selectin")

    def __repr__(self) -> str:
        return f"<BillReminder(id={self.id}, name='{self.name}', due={self.next_due_date})>"


# ──────────────────────────────────────────────────────────────
# RecurringTransaction — auto-detected recurring patterns
# ──────────────────────────────────────────────────────────────

class RecurringTransaction(Base):
    """
    Auto-detected or manually marked recurring transaction pattern.
    Detected by grouping transactions with similar merchant/description
    that appear at regular intervals.
    """
    __tablename__ = "recurring_transactions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    merchant_name: Mapped[str] = mapped_column(String(200), nullable=False)
    description_pattern: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    average_amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
    frequency: Mapped[str] = mapped_column(String(20), nullable=False)  # WEEKLY, MONTHLY, QUARTERLY, YEARLY
    category_id: Mapped[Optional[int]] = mapped_column(ForeignKey("categories.id"), nullable=True)
    last_date: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True)
    next_expected_date: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True)
    occurrence_count: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_subscription: Mapped[bool] = mapped_column(Boolean, default=False)  # user-marked as subscription
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationships
    category: Mapped[Optional["Category"]] = relationship(lazy="selectin")

    def __repr__(self) -> str:
        return f"<RecurringTransaction(id={self.id}, merchant='{self.merchant_name}', freq={self.frequency})>"
