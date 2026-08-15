"""
Classification Rule Pydantic schemas (DTOs).
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Optional, Any

from pydantic import BaseModel, ConfigDict
from app.schemas.category import CategorySchema


class ClassificationRuleCreateSchema(BaseModel):
    name: str
    pattern: Optional[str] = None
    pattern_is_regex: bool = False
    upi_handle: Optional[str] = None
    amount_min: Optional[Decimal] = None
    amount_max: Optional[Decimal] = None
    bank_filter: Optional[str] = None
    transaction_type_filter: Optional[str] = None
    target_category_id: Optional[int] = None
    target_merchant: Optional[str] = None
    mark_as_transfer: bool = False
    mark_as_excluded: bool = False
    priority: int = 100
    is_active: bool = True


class ClassificationRuleUpdateSchema(BaseModel):
    name: Optional[str] = None
    pattern: Optional[str] = None
    pattern_is_regex: Optional[bool] = None
    upi_handle: Optional[str] = None
    amount_min: Optional[Decimal] = None
    amount_max: Optional[Decimal] = None
    bank_filter: Optional[str] = None
    transaction_type_filter: Optional[str] = None
    target_category_id: Optional[int] = None
    target_merchant: Optional[str] = None
    mark_as_transfer: Optional[bool] = None
    mark_as_excluded: Optional[bool] = None
    priority: Optional[int] = None
    is_active: Optional[bool] = None


class ClassificationRuleSchema(BaseModel):
    id: int
    name: str
    pattern: Optional[str] = None
    pattern_is_regex: bool
    upi_handle: Optional[str] = None
    amount_min: Optional[Decimal] = None
    amount_max: Optional[Decimal] = None
    bank_filter: Optional[str] = None
    transaction_type_filter: Optional[str] = None
    target_category_id: Optional[int] = None
    target_merchant: Optional[str] = None
    mark_as_transfer: bool
    mark_as_excluded: bool
    priority: int
    is_active: bool
    applied_count: int
    created_at: datetime
    
    target_category: Optional[CategorySchema] = None

    model_config = ConfigDict(from_attributes=True)


class ClassificationRuleDryRunResult(BaseModel):
    matched_count: int
    sample_transactions: list[dict[str, Any]]
