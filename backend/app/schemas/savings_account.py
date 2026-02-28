"""
Savings Account Pydantic schemas (DTOs).
Replaces:
  - SavingsAccountStatementDto.java
  - SavingsAccountTransactionDto.java

FIX: Using proper Pydantic models for API responses instead of
     returning JPA entities directly (which caused JSON recursion in Java version).
"""
from __future__ import annotations

import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, computed_field

from app.models.enums import TransactionType


class SavingsAccountTransactionSchema(BaseModel):
    """Replaces: SavingsAccountTransactionDto.java"""
    id: Optional[int] = None
    date: Optional[datetime.date] = None
    description: Optional[str] = None
    reference_number: Optional[str] = None
    withdrawal_amount: Optional[Decimal] = None
    deposit_amount: Optional[Decimal] = None
    closing_balance: Optional[Decimal] = None
    type: Optional[TransactionType] = None

    model_config = ConfigDict(from_attributes=True)

    @computed_field
    @property
    def computed_type(self) -> TransactionType:
        """Replaces: SavingsAccountTransactionDto.getType() computed field"""
        if self.withdrawal_amount is not None and self.withdrawal_amount > 0:
            return TransactionType.DEBIT
        return TransactionType.CREDIT


class SavingsAccountStatementSchema(BaseModel):
    """Replaces: SavingsAccountStatementDto.java"""
    id: Optional[int] = None
    account_number: Optional[str] = None
    account_holder_name: Optional[str] = None
    ifsc_code: Optional[str] = None
    branch_name: Optional[str] = None
    from_date: Optional[datetime.date] = None
    to_date: Optional[datetime.date] = None
    opening_balance: Optional[Decimal] = None
    closing_balance: Optional[Decimal] = None
    transactions: list[SavingsAccountTransactionSchema] = []

    model_config = ConfigDict(from_attributes=True)

