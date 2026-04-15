"""
Phase 5 Pydantic schemas — Budget, SavingsGoal, BillReminder, RecurringTransaction.
"""
from __future__ import annotations

import datetime
from decimal import Decimal
from typing import Literal, Optional
from pydantic import BaseModel, ConfigDict, Field

from app.schemas.category import CategorySchema


# ──────────────────────────────────────────────────────────────
# Budget
# ──────────────────────────────────────────────────────────────

class BudgetBase(BaseModel):
    category_id: int
    year: int = Field(ge=2000, le=2100)
    month: int = Field(ge=1, le=12)
    amount: Decimal = Field(gt=0)
    rollover: bool = False
    notes: Optional[str] = None


class BudgetCreate(BudgetBase):
    """Create a new budget."""
    pass


class BudgetUpdate(BaseModel):
    """Update an existing budget (all fields optional)."""
    amount: Optional[Decimal] = Field(default=None, gt=0)
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
    target_amount: Decimal = Field(gt=0)
    current_amount: Decimal = Field(default=Decimal("0"), ge=0)
    deadline: Optional[datetime.date] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    notes: Optional[str] = None


class SavingsGoalCreate(SavingsGoalBase):
    pass


class SavingsGoalUpdate(BaseModel):
    name: Optional[str] = None
    target_amount: Optional[Decimal] = Field(default=None, gt=0)
    current_amount: Optional[Decimal] = Field(default=None, ge=0)
    deadline: Optional[datetime.date] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    notes: Optional[str] = None
    is_completed: Optional[bool] = None


class SavingsGoalSchema(SavingsGoalBase):
    """Output schema for savings goals."""
    id: int
    is_completed: bool = False
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(from_attributes=True)


# ──────────────────────────────────────────────────────────────
# BillReminder
# ──────────────────────────────────────────────────────────────

_FREQUENCY = Literal["MONTHLY", "QUARTERLY", "YEARLY", "BI_WEEKLY", "WEEKLY", "ANNUAL"]


class BillReminderBase(BaseModel):
    name: str
    amount: Optional[Decimal] = Field(default=None, gt=0)
    category_id: Optional[int] = None
    is_recurring: bool = True
    frequency: Optional[_FREQUENCY] = None
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)
    next_due_date: Optional[datetime.date] = None
    notes: Optional[str] = None


class BillReminderCreate(BillReminderBase):
    pass


class BillReminderUpdate(BaseModel):
    name: Optional[str] = None
    amount: Optional[Decimal] = Field(default=None, gt=0)
    category_id: Optional[int] = None
    is_recurring: Optional[bool] = None
    frequency: Optional[_FREQUENCY] = None
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)
    next_due_date: Optional[datetime.date] = None
    is_paid: Optional[bool] = None
    notes: Optional[str] = None


class BillReminderSchema(BillReminderBase):
    """Output schema for bill reminders."""
    id: int
    is_paid: bool = False
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(from_attributes=True)


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
