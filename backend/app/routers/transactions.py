"""
Transaction query endpoint.
Replaces: TransactionController.java

FIX: Queries BOTH savings and credit card transactions (Java version only queried savings).
"""
import logging
from datetime import date, timedelta

from fastapi import APIRouter, Query, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.savings_service import SavingsAccountStatementService
from app.services.credit_card_service import CreditCardStatementService
from app.schemas.savings_account import SavingsAccountTransactionSchema
from app.schemas.credit_card import CreditCardTransactionSchema

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/transactions", tags=["Transactions"])


@router.get("/savings", response_model=list[SavingsAccountTransactionSchema])
def get_savings_transactions(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Get savings account transactions by date range.
    Replaces: TransactionController.getTransactions(LocalDate, LocalDate)

    Defaults: from = 30 days ago, to = today (same as Java version).
    """

    transactions = SavingsAccountStatementService.get_transactions(db, from_date, to_date)
    return [SavingsAccountTransactionSchema.model_validate(t) for t in transactions]


@router.get("/credit-card", response_model=list[CreditCardTransactionSchema])
def get_credit_card_transactions(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Get credit card transactions by date range.
    FIX: This endpoint was missing in the Java version (only savings were queryable).
    """

    transactions = CreditCardStatementService.get_transactions_by_date_range(db, from_date, to_date)
    return [CreditCardTransactionSchema.model_validate(t) for t in transactions]


@router.get("", response_model=list[SavingsAccountTransactionSchema])
def get_transactions_default(
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Default transaction endpoint (savings) for backward compatibility
    with the original Java API.

    Replaces: GET /api/transactions in TransactionController.java
    """

    transactions = SavingsAccountStatementService.get_transactions(db, from_date, to_date)
    return [SavingsAccountTransactionSchema.model_validate(t) for t in transactions]
