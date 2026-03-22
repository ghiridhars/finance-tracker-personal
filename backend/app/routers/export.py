"""
Export router — CSV/JSON download of filtered transactions + data management.
Endpoints:
  GET  /api/v2/export/transactions?format=csv  — Download transactions
  POST /api/v2/data/clear-all                  — Delete all data
"""
import csv
import io
import logging
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.enums import TransactionType, SourceType
from app.services.transaction_service import UnifiedTransactionService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Export & Data Management"])


@router.get("/api/v2/export/transactions")
def export_transactions(
    format: str = Query("csv", description="Export format: csv or json"),
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    category_id: Optional[int] = Query(None),
    bank: Optional[str] = Query(None),
    source_type: Optional[SourceType] = Query(None),
    tx_type: Optional[TransactionType] = Query(None, alias="type"),
    search: Optional[str] = Query(None),
    min_amount: Optional[Decimal] = Query(None),
    max_amount: Optional[Decimal] = Query(None),
    db: Session = Depends(get_db),
):
    """
    Export filtered transactions as CSV or JSON file download.
    Uses the same filters as the unified transactions endpoint.
    """
    if from_date is None:
        from_date = date.today() - timedelta(days=90)
    if to_date is None:
        to_date = date.today()

    # Fetch up to 10000 transactions for export
    transactions = UnifiedTransactionService.query(
        db,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        bank=bank,
        source_type=source_type,
        tx_type=tx_type,
        search=search,
        min_amount=min_amount,
        max_amount=max_amount,
        limit=10000,
        offset=0,
    )

    logger.info(f"Exporting {len(transactions)} transactions as {format}")

    if format.lower() == "csv":
        return _export_csv(transactions, from_date, to_date)
    else:
        # JSON export — return as downloadable file
        import json
        rows = [_tx_to_dict(tx) for tx in transactions]
        content = json.dumps(rows, indent=2, default=str)
        return StreamingResponse(
            io.BytesIO(content.encode("utf-8")),
            media_type="application/json",
            headers={
                "Content-Disposition": f'attachment; filename="transactions_{from_date}_{to_date}.json"'
            },
        )


def _export_csv(transactions, from_date, to_date):
    """Generate CSV file from transactions."""
    output = io.StringIO()
    writer = csv.writer(output)

    # Header row
    writer.writerow([
        "Date",
        "Description",
        "Merchant",
        "Amount",
        "Type",
        "Category",
        "Bank",
        "Source Type",
        "Reference",
    ])

    # Data rows
    for tx in transactions:
        writer.writerow([
            str(tx.date) if tx.date else "",
            tx.description or "",
            tx.merchant_name or "",
            str(tx.amount) if tx.amount else "0",
            tx.type.value if tx.type else "",
            tx.category.name if tx.category else "",
            tx.bank or "",
            tx.source_type.value if tx.source_type else "",
            tx.reference_number or "",
        ])

    output.seek(0)
    return StreamingResponse(
        io.BytesIO(output.getvalue().encode("utf-8")),
        media_type="text/csv",
        headers={
            "Content-Disposition": f'attachment; filename="transactions_{from_date}_{to_date}.csv"'
        },
    )


def _tx_to_dict(tx):
    """Convert transaction ORM object to dictionary."""
    return {
        "date": str(tx.date) if tx.date else None,
        "description": tx.description,
        "merchant_name": tx.merchant_name,
        "amount": float(tx.amount) if tx.amount else 0,
        "type": tx.type.value if tx.type else None,
        "category": tx.category.name if tx.category else None,
        "bank": tx.bank,
        "source_type": tx.source_type.value if tx.source_type else None,
        "reference": tx.reference_number,
    }


@router.post("/api/v2/data/clear-all")
def clear_all_data(db: Session = Depends(get_db)):
    """
    Delete ALL user data: transactions, statements, accounts, budgets,
    goals, reminders, and recurring patterns. Categories are preserved.
    """
    from app.models.savings_account import SavingsAccountTransaction, SavingsAccountStatement
    from app.models.credit_card import CreditCardTransaction, CreditCardStatement
    from app.models.budget import Budget, SavingsGoal, BillReminder, RecurringTransaction
    from app.models.transaction import UnifiedTransaction

    tables_to_clear = [
        RecurringTransaction,
        BillReminder,
        SavingsGoal,
        Budget,
        UnifiedTransaction,
        CreditCardTransaction,
        SavingsAccountTransaction,
        CreditCardStatement,
        SavingsAccountStatement,
    ]

    total_deleted = 0
    for model in tables_to_clear:
        try:
            count = db.query(model).delete()
            total_deleted += count
            logger.info(f"Cleared {count} rows from {model.__tablename__}")
        except Exception as e:
            logger.warning(f"Could not clear {model}: {e}")
            db.rollback()

    db.commit()
    logger.info(f"Clear all data: {total_deleted} total rows deleted")
    return {"message": f"Cleared {total_deleted} records", "deleted": total_deleted}
