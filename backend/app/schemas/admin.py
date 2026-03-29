"""
Admin / Database Manager Pydantic schemas.
"""
from __future__ import annotations

from typing import Any, Optional
from pydantic import BaseModel


class TableInfo(BaseModel):
    name: str
    column_count: int
    row_count: int


class ForeignKeyInfo(BaseModel):
    table: str
    column: str


class ColumnInfo(BaseModel):
    name: str
    type: str
    nullable: bool = True
    primary_key: bool = False
    autoincrement: bool = False
    max_length: Optional[int] = None
    foreign_key: Optional[ForeignKeyInfo] = None
    enum_values: Optional[list[str]] = None
    default: Optional[str] = None


class TableSchema(BaseModel):
    name: str
    columns: list[ColumnInfo]


class RowsResponse(BaseModel):
    rows: list[dict[str, Any]]
    total: int
    limit: int
    offset: int


class FKOption(BaseModel):
    id: Any
    label: str
