"""
Credit Card Pydantic schemas (DTOs).
Replaces:
  - CreditCardStatementDto.java
  - CreditCardTransactionDto.java

FIX: Using proper Pydantic models for API responses instead of
     returning JPA entities directly (which caused JSON recursion in Java version).
"""
from __future__ import annotations

import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict

from app.models.enums import TransactionType


class CreditCardTransactionSchema(BaseModel):
    """Replaces: CreditCardTransactionDto.java"""
    id: Optional[int] = None
    date: Optional[datetime.date] = None
    description: Optional[str] = None
    amount: Optional[Decimal] = None
    type: Optional[TransactionType] = None
    reference_number: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class CreditCardStatementSchema(BaseModel):
    """Replaces: CreditCardStatementDto.java"""
    id: Optional[int] = None
    statement_date: Optional[datetime.date] = None
    due_date: Optional[datetime.date] = None
    card_number: Optional[str] = None
    card_holder_name: Optional[str] = None
    credit_limit: Optional[Decimal] = None
    available_credit: Optional[Decimal] = None
    total_dues: Optional[Decimal] = None
    minimum_amount_due: Optional[Decimal] = None
    transactions: list[CreditCardTransactionSchema] = []

    model_config = ConfigDict(from_attributes=True)
