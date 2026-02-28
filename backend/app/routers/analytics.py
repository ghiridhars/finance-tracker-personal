"""
Analytics router — dashboard data endpoints.

All endpoints return aggregate data from unified_transactions.
"""
from datetime import date, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.analytics_service import AnalyticsService

router = APIRouter(prefix="/api/v2/analytics", tags=["Analytics"])


@router.get("/summary")
def get_summary(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Dashboard summary: income, spending, net savings, transaction count,
    top category, active banks.
    Defaults to last 30 days.
    """
    return AnalyticsService.get_summary(
        db, from_date=from_date, to_date=to_date
    )


@router.get("/spending-by-category")
def spending_by_category(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Spending breakdown by category (for pie/donut chart).
    Returns category name, color, icon, amount, percentage, tx count.
    """
    return AnalyticsService.spending_by_category(
        db, from_date=from_date, to_date=to_date
    )


@router.get("/spending-trends")
def spending_trends(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    granularity: str = Query("daily", regex="^(daily|weekly|monthly)$"),
    db: Session = Depends(get_db),
):
    """
    Time-series spending and income (for line/area chart).
    Granularity: daily, weekly, or monthly.
    """
    return AnalyticsService.spending_trends(
        db, from_date=from_date, to_date=to_date, granularity=granularity
    )


@router.get("/income-vs-expense")
def income_vs_expense(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Monthly income vs expense (for bar chart).
    Defaults to last 12 months.
    """
    return AnalyticsService.income_vs_expense(
        db, from_date=from_date, to_date=to_date
    )


@router.get("/month-over-month")
def month_over_month(
    ref_month: Optional[date] = Query(None, alias="month"),
    db: Session = Depends(get_db),
):
    """
    Compare current month vs previous month spending by category.
    Pass ?month=2026-02-01 to specify reference month.
    """
    return AnalyticsService.month_over_month(db, ref_month=ref_month)


@router.get("/top-merchants")
def top_merchants(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    limit: int = Query(15, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """
    Top merchants by spending amount.
    """
    return AnalyticsService.top_merchants(
        db, from_date=from_date, to_date=to_date, limit=limit
    )


@router.get("/spending-by-bank")
def spending_by_bank(
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    db: Session = Depends(get_db),
):
    """
    Spending grouped by bank (for bank comparison view).
    """
    return AnalyticsService.spending_by_bank(
        db, from_date=from_date, to_date=to_date
    )
