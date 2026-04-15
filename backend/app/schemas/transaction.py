"""
UnifiedTransaction Pydantic schemas (DTOs).
"""
from __future__ import annotations

import datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import TransactionType, SourceType, TransferType
from app.schemas.category import CategorySchema
from app.schemas.tag import TagSchema


class UnifiedTransactionSchema(BaseModel):
    id: Optional[int] = None
    date: Optional[datetime.date] = None
    description: Optional[str] = None
    amount: Optional[Decimal] = None
    type: Optional[TransactionType] = None
    source_type: Optional[SourceType] = None
    source_transaction_id: Optional[int] = None
    bank: Optional[str] = None
    account_identifier: Optional[str] = None
    category_id: Optional[int] = None
    category: Optional[CategorySchema] = None
    merchant_name: Optional[str] = None
    notes: Optional[str] = None
    reference_number: Optional[str] = None
    is_transfer: bool = False
    transfer_group_id: Optional[str] = None
    transfer_type: Optional[TransferType] = None
    tags: list[TagSchema] = []
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(from_attributes=True)


class TransactionUpdateSchema(BaseModel):
    """Input schema for updating a unified transaction (re-categorize, tag, notes)."""
    category_id: Optional[int] = None
    merchant_name: Optional[str] = None
    notes: Optional[str] = None
    tag_ids: Optional[list[int]] = None


class TransactionQueryParams(BaseModel):
    """Query filter parameters for listing transactions."""
    from_date: Optional[datetime.date] = None
    to_date: Optional[datetime.date] = None
    category_id: Optional[int] = None
    bank: Optional[str] = None
    account_identifier: Optional[str] = None
    source_type: Optional[SourceType] = None
    type: Optional[TransactionType] = None
    search: Optional[str] = None
    min_amount: Optional[Decimal] = Field(default=None, ge=0)
    max_amount: Optional[Decimal] = Field(default=None, ge=0)
    limit: int = Field(default=100, ge=1, le=1000)
    offset: int = Field(default=0, ge=0)


# ── Transfer linking schemas ─────────────────────────────────

class TransferLinkRequest(BaseModel):
    """Request to manually link two transactions as a transfer pair."""
    transaction_id_1: int
    transaction_id_2: int
    transfer_type: TransferType = TransferType.INTERNAL_TRANSFER


class TransferPairSchema(BaseModel):
    """Response schema for a linked transfer pair."""
    transfer_group_id: str
    transfer_type: Optional[TransferType] = None
    transactions: list[UnifiedTransactionSchema] = []


class TransferDetectResult(BaseModel):
    """Response from auto-detection: how many pairs were linked."""
    linked_count: int
    details: list[TransferPairSchema] = []
