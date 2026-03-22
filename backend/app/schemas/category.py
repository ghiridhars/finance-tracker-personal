"""
Category Pydantic schemas (DTOs).
"""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, ConfigDict


class CategoryKeywordSchema(BaseModel):
    id: Optional[int] = None
    keyword: str
    category_id: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class MccCategorySchema(BaseModel):
    id: Optional[int] = None
    mcc_code: str
    description: Optional[str] = None
    category_id: int

    model_config = ConfigDict(from_attributes=True)


class CategorySchema(BaseModel):
    id: Optional[int] = None
    name: str
    icon: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[int] = None
    is_system: bool = True
    keywords: list[CategoryKeywordSchema] = []

    model_config = ConfigDict(from_attributes=True)


class CategoryCreateSchema(BaseModel):
    """Input schema for creating a category."""
    name: str
    icon: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[int] = None
    keywords: list[str] = []


class CategoryUpdateSchema(BaseModel):
    """Input schema for updating a category."""
    name: Optional[str] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    parent_id: Optional[int] = None


class KeywordAddSchema(BaseModel):
    """Input schema for adding keywords to a category."""
    keywords: list[str]
