"""
Tag Pydantic schemas (DTOs).
"""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, ConfigDict


class TagSchema(BaseModel):
    id: Optional[int] = None
    name: str
    color: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class TagCreateSchema(BaseModel):
    name: str
    color: Optional[str] = None
