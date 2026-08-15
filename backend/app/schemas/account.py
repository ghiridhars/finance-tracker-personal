"""
Account Pydantic schemas (DTOs).
"""
from __future__ import annotations

from datetime import date as date_type, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict


class AccountCreateSchema(BaseModel):
    bank_name: str
    account_type: str
    name: str
    account_number: Optional[str] = None
    holder_name: Optional[str] = None
    ifsc_code: Optional[str] = None
    account_subtype: Optional[str] = None
    notes: Optional[str] = None
    loan_principal: Optional[Decimal] = None
    loan_interest_rate: Optional[Decimal] = None
    loan_emi_amount: Optional[Decimal] = None
    loan_start_date: Optional[date_type] = None
    loan_end_date: Optional[date_type] = None
    credit_limit: Optional[Decimal] = None
    billing_cycle_day: Optional[int] = None
    invested_amount: Optional[Decimal] = None
    current_value: Optional[Decimal] = None
    value_updated_at: Optional[datetime] = None


class AccountUpdateSchema(BaseModel):
    bank_name: Optional[str] = None
    account_type: Optional[str] = None
    name: Optional[str] = None
    account_number: Optional[str] = None
    holder_name: Optional[str] = None
    ifsc_code: Optional[str] = None
    account_subtype: Optional[str] = None
    notes: Optional[str] = None
    loan_principal: Optional[Decimal] = None
    loan_interest_rate: Optional[Decimal] = None
    loan_emi_amount: Optional[Decimal] = None
    loan_start_date: Optional[date_type] = None
    loan_end_date: Optional[date_type] = None
    credit_limit: Optional[Decimal] = None
    billing_cycle_day: Optional[int] = None
    invested_amount: Optional[Decimal] = None
    current_value: Optional[Decimal] = None
    value_updated_at: Optional[datetime] = None


class AccountMergeSchema(BaseModel):
    source_account_id: int
    target_account_id: int


class AccountSchema(BaseModel):
    id: int
    bank_name: str
    account_type: str
    name: str
    account_number: Optional[str] = None
    holder_name: Optional[str] = None
    ifsc_code: Optional[str] = None
    is_active: bool
    created_at: datetime
    
    account_subtype: Optional[str] = None
    loan_principal: Optional[Decimal] = None
    loan_interest_rate: Optional[Decimal] = None
    loan_emi_amount: Optional[Decimal] = None
    loan_start_date: Optional[date_type] = None
    loan_end_date: Optional[date_type] = None
    credit_limit: Optional[Decimal] = None
    billing_cycle_day: Optional[int] = None
    invested_amount: Optional[Decimal] = None
    current_value: Optional[Decimal] = None
    value_updated_at: Optional[datetime] = None
    notes: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
