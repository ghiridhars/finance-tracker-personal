"""
UPI ID Pydantic schemas (DTOs).
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, field_validator


class UpiIdSchema(BaseModel):
    """Full UPI ID representation returned from the API."""
    id: Optional[int] = None
    upi_handle: str
    label: Optional[str] = None
    account_type: Optional[str] = None
    account_identifier: Optional[str] = None
    category_id: Optional[int] = None
    is_own: bool = False
    created_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class UpiIdCreateSchema(BaseModel):
    """Schema for creating a new UPI ID mapping."""
    upi_handle: str
    label: Optional[str] = None
    account_type: Optional[str] = None
    account_identifier: Optional[str] = None
    category_id: Optional[int] = None
    is_own: bool = False

    @field_validator("upi_handle")
    @classmethod
    def validate_upi_handle(cls, v: str) -> str:
        v = v.strip().lower()
        if "@" not in v:
            raise ValueError("UPI handle must contain '@' (e.g. user@bank)")
        return v


class UpiIdUpdateSchema(BaseModel):
    """Schema for updating an existing UPI ID mapping."""
    label: Optional[str] = None
    account_type: Optional[str] = None
    account_identifier: Optional[str] = None
    category_id: Optional[int] = None
    is_own: Optional[bool] = None
