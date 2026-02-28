"""
Phase 5 Pydantic schemas — Budget, SavingsGoal, BillReminder, RecurringTransaction.
"""
from __future__ import annotations

import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict

from app.schemas.category import CategorySchema


# ──────────────────────────────────────────────────────────────
# Budget
# ──────────────────────────────────────────────────────────────

class BudgetBase(BaseModel):
    category_id: int
    year: int
    month: int
    amount: Decimal
    rollover: bool = False
    notes: Optional[str] = None


class BudgetCreate(BudgetBase):
    """Create a new budget."""
    pass


class BudgetUpdate(BaseModel):
    """Update an existing budget (all fields optional)."""
    amount: Optional[Decimal] = None
    rollover: Optional[bool] = None
    notes: Optional[str] = None


class BudgetSchema(BudgetBase):
    id: int
    created_at: Optional[datetime.datetime] = None
    category: Optional[CategorySchema] = None

    model_config = ConfigDict(from_attributes=True)


# ──────────────────────────────────────────────────────────────
# SavingsGoal
# ──────────────────────────────────────────────────────────────

class SavingsGoalBase(BaseModel):
    name: str
    target_amount: Decimal
    current_amount: Decimal = Decimal("0")
    deadline: Optional[datetime.date] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    notes: Optional[str] = None


class SavingsGoalCreate(SavingsGoalBase):
    pass


class SavingsGoalUpdate(BaseModel):
    name: Optional[str] = None
    target_amount: Optional[Decimal] = None
    current_amount: Optional[Decimal] = None
    deadline: Optional[datetime.date] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    notes: Optional[str] = None
    is_completed: Optional[bool] = None


# ──────────────────────────────────────────────────────────────
# BillReminder
# ──────────────────────────────────────────────────────────────

class BillReminderBase(BaseModel):
    name: str
    amount: Optional[Decimal] = None
    category_id: Optional[int] = None
    is_recurring: bool = True
    frequency: Optional[str] = None  # MONTHLY, QUARTERLY, YEARLY
    day_of_month: Optional[int] = None
    next_due_date: Optional[datetime.date] = None
    notes: Optional[str] = None


class BillReminderCreate(BillReminderBase):
    pass


class BillReminderUpdate(BaseModel):
    name: Optional[str] = None
    amount: Optional[Decimal] = None
    category_id: Optional[int] = None
    is_recurring: Optional[bool] = None
    frequency: Optional[str] = None
    day_of_month: Optional[int] = None
    next_due_date: Optional[datetime.date] = None
    is_paid: Optional[bool] = None
    notes: Optional[str] = None


# ──────────────────────────────────────────────────────────────
# RecurringTransaction
# ──────────────────────────────────────────────────────────────

class RecurringTransactionSchema(BaseModel):
    id: int
    merchant_name: str
    description_pattern: Optional[str] = None
    average_amount: Decimal
    frequency: str
    category_id: Optional[int] = None
    category: Optional[CategorySchema] = None
    last_date: Optional[datetime.date] = None
    next_expected_date: Optional[datetime.date] = None
    occurrence_count: int = 0
    is_active: bool = True
    is_subscription: bool = False
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(from_attributes=True)
