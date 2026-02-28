"""
Budget management router.

Endpoints:
  - GET    /api/v2/budgets?year=&month=           — List budgets for a month
  - GET    /api/v2/budgets/progress?year=&month=   — Budget vs actual spending
  - GET    /api/v2/budgets/summary?year=&month=    — Overall budget summary
  - POST   /api/v2/budgets                         — Create budget
  - POST   /api/v2/budgets/copy                    — Copy budgets to new month
  - PATCH  /api/v2/budgets/{id}                    — Update budget
  - DELETE /api/v2/budgets/{id}                    — Delete budget
"""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.budget_service import BudgetService
from app.schemas.budget import BudgetCreate, BudgetUpdate, BudgetSchema

router = APIRouter(prefix="/api/v2/budgets", tags=["Budgets"])


@router.get("")
def list_budgets(
    year: int = Query(default=None),
    month: int = Query(default=None),
    db: Session = Depends(get_db),
):
    """List budgets for a given month (defaults to current month)."""
    today = date.today()
    y = year or today.year
    m = month or today.month
    budgets = BudgetService.list_budgets(db, y, m)
    return [BudgetSchema.model_validate(b) for b in budgets]


@router.get("/progress")
def budget_progress(
    year: int = Query(default=None),
    month: int = Query(default=None),
    db: Session = Depends(get_db),
):
    """Get budget vs actual spending for each category."""
    today = date.today()
    y = year or today.year
    m = month or today.month
    return BudgetService.get_progress(db, y, m)


@router.get("/summary")
def budget_summary(
    year: int = Query(default=None),
    month: int = Query(default=None),
    db: Session = Depends(get_db),
):
    """Overall budget summary: total budgeted, total spent, per-category breakdown."""
    today = date.today()
    y = year or today.year
    m = month or today.month
    return BudgetService.get_summary(db, y, m)


@router.post("", response_model=BudgetSchema)
def create_budget(data: BudgetCreate, db: Session = Depends(get_db)):
    """Create a monthly budget for a category."""
    try:
        budget = BudgetService.create(
            db,
            category_id=data.category_id,
            year=data.year,
            month=data.month,
            amount=data.amount,
            rollover=data.rollover,
            notes=data.notes,
        )
        return BudgetSchema.model_validate(budget)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/copy")
def copy_budgets(
    from_year: int = Query(...),
    from_month: int = Query(...),
    to_year: int = Query(...),
    to_month: int = Query(...),
    db: Session = Depends(get_db),
):
    """Copy all budgets from one month to another."""
    created = BudgetService.copy_to_month(db, from_year, from_month, to_year, to_month)
    return {"copied": len(created)}


@router.patch("/{budget_id}", response_model=BudgetSchema)
def update_budget(budget_id: int, data: BudgetUpdate, db: Session = Depends(get_db)):
    kwargs = {}
    if data.amount is not None:
        kwargs["amount"] = data.amount
    if data.rollover is not None:
        kwargs["rollover"] = data.rollover
    if data.notes is not None:
        kwargs["notes"] = data.notes

    budget = BudgetService.update(db, budget_id, **kwargs)
    if not budget:
        raise HTTPException(status_code=404, detail="Budget not found")
    return BudgetSchema.model_validate(budget)


@router.delete("/{budget_id}")
def delete_budget(budget_id: int, db: Session = Depends(get_db)):
    if not BudgetService.delete(db, budget_id):
        raise HTTPException(status_code=404, detail="Budget not found")
    return {"detail": "Budget deleted", "id": budget_id}
