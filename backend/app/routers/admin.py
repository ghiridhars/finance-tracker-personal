"""
Generic database admin router.

Provides table introspection, paginated row browsing, and full CRUD
for a configurable allowlist of tables. All table/column names are
validated against the allowlist and schema before use — queries are
built with SQLAlchemy Core (parameterized), never raw string interpolation.
"""
import logging
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, inspect as sa_inspect, select, text
from sqlalchemy.engine import Engine

from app.database import Base, engine, get_db, SessionLocal
from app.schemas.admin import (
    ColumnInfo,
    FKOption,
    ForeignKeyInfo,
    RowsResponse,
    TableInfo,
    TableSchema,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/admin", tags=["admin"])

# ── Allowlist ────────────────────────────────────────────────
# Only these tables are exposed via the admin API.
ALLOWED_TABLES: set[str] = {
    "bank_accounts",
    "categories",
    "mcc_categories",
    "unified_transactions",
    "statement_audit",
    "upi_ids",
    "classification_rules",
    "investment_rules",
    "asset_classes",
}


def _validate_table(table_name: str):
    """Return the SQLAlchemy Table object or raise 404."""
    if table_name not in ALLOWED_TABLES:
        raise HTTPException(status_code=404, detail=f"Table '{table_name}' not found or not allowed")
    table = Base.metadata.tables.get(table_name)
    if table is None:
        raise HTTPException(status_code=404, detail=f"Table '{table_name}' does not exist in metadata")
    return table


def _col_type_str(col) -> str:
    """Map a SQLAlchemy column type to a simple string."""
    from sqlalchemy import Integer, String, Text, Boolean, Date, DateTime, Numeric, Float, Enum as SAEnum
    t = type(col.type)
    if t in (Integer,) or "INTEGER" in str(col.type).upper():
        return "integer"
    if t in (String,):
        return "string"
    if t in (Text,):
        return "text"
    if t in (Boolean,):
        return "boolean"
    if t in (Date,):
        return "date"
    if t in (DateTime,):
        return "datetime"
    if t in (Numeric, Float):
        return "number"
    if t in (SAEnum,):
        return "enum"
    return str(col.type).lower()


def _col_info(col) -> ColumnInfo:
    """Build a ColumnInfo from a SQLAlchemy Column."""
    from sqlalchemy import Enum as SAEnum, String

    fk = None
    if col.foreign_keys:
        fk_obj = next(iter(col.foreign_keys))
        fk = ForeignKeyInfo(table=fk_obj.column.table.name, column=fk_obj.column.name)

    enum_values = None
    if isinstance(col.type, SAEnum) and col.type.enums:
        enum_values = list(col.type.enums)

    max_length = None
    if isinstance(col.type, String) and col.type.length:
        max_length = col.type.length

    default_val = None
    if col.server_default is not None:
        default_val = str(col.server_default.arg)

    return ColumnInfo(
        name=col.name,
        type=_col_type_str(col),
        nullable=col.nullable if col.nullable is not None else True,
        primary_key=col.primary_key,
        autoincrement=getattr(col, "autoincrement", False) is True,
        max_length=max_length,
        foreign_key=fk,
        enum_values=enum_values,
        default=default_val,
    )


def _serialize_row(row, columns) -> dict[str, Any]:
    """Convert a SQLAlchemy row to a JSON-safe dict."""
    result: dict[str, Any] = {}
    for col in columns:
        val = row._mapping[col.name]
        if isinstance(val, (date, datetime)):
            val = val.isoformat()
        elif isinstance(val, Decimal):
            val = float(val)
        result[col.name] = val
    return result


def _coerce_value(value: Any, col) -> Any:
    """Coerce a JSON value to the appropriate Python type for a column."""
    if value is None:
        return None
    col_type = _col_type_str(col)
    if col_type == "integer":
        return int(value)
    if col_type == "number":
        return Decimal(str(value))
    if col_type == "boolean":
        if isinstance(value, bool):
            return value
        return str(value).lower() in ("true", "1", "yes")
    if col_type == "date":
        if isinstance(value, str):
            return date.fromisoformat(value)
        return value
    if col_type == "datetime":
        if isinstance(value, str):
            return datetime.fromisoformat(value)
        return value
    return value


# ── Endpoints ────────────────────────────────────────────────

@router.get("/tables", response_model=list[TableInfo])
def list_tables():
    """List all allowed tables with column count and row count."""
    results: list[TableInfo] = []
    with engine.connect() as conn:
        for table_name in sorted(ALLOWED_TABLES):
            table = Base.metadata.tables.get(table_name)
            if table is None:
                continue
            count = conn.execute(select(func.count()).select_from(table)).scalar() or 0
            results.append(TableInfo(
                name=table_name,
                column_count=len(table.columns),
                row_count=count,
            ))
    return results


@router.get("/tables/{table_name}/schema", response_model=TableSchema)
def get_table_schema(table_name: str):
    """Return column metadata for a table."""
    table = _validate_table(table_name)
    columns = [_col_info(col) for col in table.columns]
    return TableSchema(name=table_name, columns=columns)


@router.get("/tables/{table_name}/rows", response_model=RowsResponse)
def list_rows(
    table_name: str,
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    sort: Optional[str] = Query(None),
    order: str = Query("asc", pattern="^(asc|desc)$"),
    search: Optional[str] = Query(None),
    search_column: Optional[str] = Query(None),
):
    """Paginated row listing with optional sort and search."""
    table = _validate_table(table_name)

    # Validate sort column
    if sort and sort not in {c.name for c in table.columns}:
        raise HTTPException(status_code=400, detail=f"Invalid sort column: '{sort}'")

    with engine.connect() as conn:
        # Base query
        query = select(table)

        # Search
        if search:
            from sqlalchemy import or_, cast, String as SAString
            
            if search_column and search_column in {c.name for c in table.columns}:
                # Search specific column
                col = table.c[search_column]
                # Cast to string for generic ilike search
                query = query.where(cast(col, SAString).ilike(f"%{search}%"))
            else:
                # Search across all string/text columns
                like_clauses = []
                for col in table.columns:
                    col_type = _col_type_str(col)
                    if col_type in ("string", "text"):
                        like_clauses.append(col.ilike(f"%{search}%"))
                if like_clauses:
                    query = query.where(or_(*like_clauses))

        # Count total matches
        count_query = select(func.count()).select_from(query.subquery())
        total = conn.execute(count_query).scalar() or 0

        # Sort
        if sort:
            sort_col = table.c[sort]
            query = query.order_by(sort_col.desc() if order == "desc" else sort_col.asc())
        else:
            # Default: sort by first PK column
            pk_cols = [c for c in table.columns if c.primary_key]
            if pk_cols:
                query = query.order_by(pk_cols[0].desc())

        # Paginate
        query = query.limit(limit).offset(offset)
        rows = conn.execute(query).fetchall()

    return RowsResponse(
        rows=[_serialize_row(r, table.columns) for r in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post("/tables/{table_name}/rows", status_code=201)
def create_row(table_name: str, data: dict[str, Any]):
    """Insert a new row. Autoincrement PK columns are stripped automatically."""
    table = _validate_table(table_name)

    # Strip autoincrement PK columns
    valid_cols = {c.name for c in table.columns}
    auto_pk_cols = {c.name for c in table.columns if c.primary_key and c.autoincrement is not False}

    insert_data: dict[str, Any] = {}
    for key, value in data.items():
        if key not in valid_cols:
            continue
        if key in auto_pk_cols:
            continue
        col = table.c[key]
        try:
            insert_data[key] = _coerce_value(value, col)
        except (ValueError, InvalidOperation) as e:
            raise HTTPException(status_code=400, detail=f"Invalid value for '{key}': {e}")

    with engine.begin() as conn:
        try:
            result = conn.execute(table.insert().values(**insert_data))
            pk = result.inserted_primary_key[0] if result.inserted_primary_key else None
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))

        # Re-fetch the inserted row
        if pk is not None:
            pk_col = [c for c in table.columns if c.primary_key][0]
            row = conn.execute(select(table).where(pk_col == pk)).fetchone()
            if row:
                return _serialize_row(row, table.columns)
    return insert_data


@router.put("/tables/{table_name}/rows/{row_id}")
def update_row(table_name: str, row_id: int, data: dict[str, Any]):
    """Update an existing row by its primary key."""
    table = _validate_table(table_name)

    pk_cols = [c for c in table.columns if c.primary_key]
    if not pk_cols:
        raise HTTPException(status_code=400, detail="Table has no primary key")
    pk_col = pk_cols[0]

    # Strip PK columns from payload
    valid_cols = {c.name for c in table.columns}
    pk_names = {c.name for c in pk_cols}

    update_data: dict[str, Any] = {}
    for key, value in data.items():
        if key not in valid_cols or key in pk_names:
            continue
        col = table.c[key]
        try:
            update_data[key] = _coerce_value(value, col)
        except (ValueError, InvalidOperation) as e:
            raise HTTPException(status_code=400, detail=f"Invalid value for '{key}': {e}")

    if not update_data:
        raise HTTPException(status_code=400, detail="No valid fields to update")

    with engine.begin() as conn:
        try:
            result = conn.execute(
                table.update().where(pk_col == row_id).values(**update_data)
            )
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))

        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Row not found")

        # Re-fetch
        row = conn.execute(select(table).where(pk_col == row_id)).fetchone()
        if row:
            return _serialize_row(row, table.columns)
    return update_data


@router.delete("/tables/{table_name}/rows/{row_id}")
def delete_row(table_name: str, row_id: int):
    """Delete a row by its primary key."""
    table = _validate_table(table_name)

    pk_cols = [c for c in table.columns if c.primary_key]
    if not pk_cols:
        raise HTTPException(status_code=400, detail="Table has no primary key")
    pk_col = pk_cols[0]

    from sqlalchemy.exc import IntegrityError

    with engine.begin() as conn:
        try:
            result = conn.execute(table.delete().where(pk_col == row_id))
            if result.rowcount == 0:
                raise HTTPException(status_code=404, detail="Row not found")
        except IntegrityError:
            raise HTTPException(
                status_code=400, 
                detail="Cannot delete this row because it is referenced by other records. Please delete the dependent records first."
            )
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))

    return {"detail": "Deleted"}


@router.get("/tables/{table_name}/fk-options/{column_name}", response_model=list[FKOption])
def get_fk_options(table_name: str, column_name: str):
    """Return dropdown options for a foreign key column."""
    table = _validate_table(table_name)

    # Find the column
    if column_name not in {c.name for c in table.columns}:
        raise HTTPException(status_code=404, detail=f"Column '{column_name}' not found")

    col = table.c[column_name]
    if not col.foreign_keys:
        raise HTTPException(status_code=400, detail=f"Column '{column_name}' is not a foreign key")

    fk_obj = next(iter(col.foreign_keys))
    target_table_name = fk_obj.column.table.name
    target_table = Base.metadata.tables.get(target_table_name)
    if target_table is None:
        raise HTTPException(status_code=404, detail=f"Referenced table '{target_table_name}' not found")

    # Find id column and display column
    target_pk = [c for c in target_table.columns if c.primary_key]
    if not target_pk:
        raise HTTPException(status_code=400, detail="Referenced table has no primary key")
    id_col = target_pk[0]

    # Heuristic: prefer name, then description, then label, then first string column
    display_col = None
    for candidate in ("name", "description", "label", "title"):
        if candidate in {c.name for c in target_table.columns}:
            display_col = target_table.c[candidate]
            break
    if display_col is None:
        # Fall back to first string column
        for c in target_table.columns:
            if _col_type_str(c) in ("string", "text"):
                display_col = c
                break

    with engine.connect() as conn:
        if display_col is not None:
            rows = conn.execute(
                select(id_col, display_col).order_by(display_col)
            ).fetchall()
            return [
                FKOption(id=row._mapping[id_col.name], label=str(row._mapping[display_col.name] or f"ID: {row._mapping[id_col.name]}"))
                for row in rows
            ]
        else:
            rows = conn.execute(select(id_col).order_by(id_col)).fetchall()
            return [
                FKOption(id=row._mapping[id_col.name], label=f"ID: {row._mapping[id_col.name]}")
                for row in rows
            ]
