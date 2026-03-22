"""
Budget service — CRUD + progress tracking against actual spending.
"""
import logging
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy import func, extract
from sqlalchemy.orm import Session

from app.models.budget import Budget
from app.models.transaction import UnifiedTransaction
from app.models.enums import TransactionType

logger = logging.getLogger(__name__)


class BudgetService:
    """Monthly category budgets with progress tracking."""

    # ── CRUD ─────────────────────────────────────────────

    @staticmethod
    def create(db: Session, *, category_id: int, year: int, month: int,
               amount: Decimal, rollover: bool = False, notes: str | None = None) -> Budget:
        budget = Budget(
            category_id=category_id, year=year, month=month,
            amount=amount, rollover=rollover, notes=notes,
        )
        db.add(budget)
        db.commit()
        db.refresh(budget)
        logger.info(f"Created budget id={budget.id} for cat={category_id} {year}-{month:02d} amt={amount}")
        return budget

    @staticmethod
    def update(db: Session, budget_id: int, **kwargs) -> Budget | None:
        budget = db.query(Budget).filter(Budget.id == budget_id).first()
        if not budget:
            return None
        for k, v in kwargs.items():
            if v is not None and hasattr(budget, k):
                setattr(budget, k, v)
        db.commit()
        db.refresh(budget)
        return budget

    @staticmethod
    def delete(db: Session, budget_id: int) -> bool:
        budget = db.query(Budget).filter(Budget.id == budget_id).first()
        if not budget:
            return False
        db.delete(budget)
        db.commit()
        return True

    @staticmethod
    def list_budgets(db: Session, year: int, month: int) -> list[Budget]:
        return (
            db.query(Budget)
            .filter(Budget.year == year, Budget.month == month)
            .all()
        )

    # ── Copy budgets to new month ────────────────────────

    @staticmethod
    def copy_to_month(db: Session, from_year: int, from_month: int,
                      to_year: int, to_month: int) -> list[Budget]:
        """Copy all budgets from one month to another (skip existing)."""
        source = BudgetService.list_budgets(db, from_year, from_month)
        created = []
        for b in source:
            existing = (
                db.query(Budget)
                .filter(Budget.year == to_year, Budget.month == to_month,
                        Budget.category_id == b.category_id)
                .first()
            )
            if existing:
                continue
            new_b = Budget(
                category_id=b.category_id, year=to_year, month=to_month,
                amount=b.amount, rollover=b.rollover,
            )
            db.add(new_b)
            created.append(new_b)
        db.commit()
        for b in created:
            db.refresh(b)
        logger.info(f"Copied {len(created)} budgets from {from_year}-{from_month:02d} to {to_year}-{to_month:02d}")
        return created

    # ── Progress / spending tracking ─────────────────────

    @staticmethod
    def _get_spent(db: Session, category_id: int, year: int, month: int) -> Decimal:
        """Sum of DEBIT transactions for a category in a given month."""
        result = (
            db.query(func.coalesce(func.sum(UnifiedTransaction.amount), 0))
            .filter(
                UnifiedTransaction.category_id == category_id,
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                extract("year", UnifiedTransaction.date) == year,
                extract("month", UnifiedTransaction.date) == month,
            )
            .scalar()
        )
        return Decimal(str(result))

    @staticmethod
    def _get_rollover(db: Session, category_id: int, year: int, month: int) -> Decimal:
        """
        Compute rollover: unspent from previous month's budget (if rollover=True).
        """
        # Find previous month
        if month == 1:
            prev_year, prev_month = year - 1, 12
        else:
            prev_year, prev_month = year, month - 1

        prev_budget = (
            db.query(Budget)
            .filter(
                Budget.category_id == category_id,
                Budget.year == prev_year,
                Budget.month == prev_month,
                Budget.rollover == True,
            )
            .first()
        )
        if not prev_budget:
            return Decimal("0")

        prev_spent = BudgetService._get_spent(db, category_id, prev_year, prev_month)
        unspent = prev_budget.amount - prev_spent
        return max(unspent, Decimal("0"))

    @staticmethod
    def get_progress(db: Session, year: int, month: int) -> list[dict]:
        """
        Return budget progress for every budgeted category in a month.
        Each entry: {id, category_id, category_name, category_color, category_icon,
                     year, month, budget_amount, spent_amount, remaining,
                     percentage_used, rollover_amount, is_over_budget}
        """
        budgets = BudgetService.list_budgets(db, year, month)
        results = []
        for b in budgets:
            spent = BudgetService._get_spent(db, b.category_id, year, month)
            rollover = BudgetService._get_rollover(db, b.category_id, year, month) if b.rollover else Decimal("0")
            effective_budget = b.amount + rollover
            remaining = effective_budget - spent
            pct = float(spent / effective_budget * 100) if effective_budget > 0 else 0.0

            results.append({
                "id": b.id,
                "category_id": b.category_id,
                "category_name": b.category.name if b.category else "Unknown",
                "category_color": b.category.color if b.category else None,
                "category_icon": b.category.icon if b.category else None,
                "year": year,
                "month": month,
                "budget_amount": float(effective_budget),
                "spent_amount": float(spent),
                "remaining": float(remaining),
                "percentage_used": round(pct, 1),
                "rollover_amount": float(rollover),
                "is_over_budget": spent > effective_budget,
            })

        # Sort: over-budget first, then by percentage used descending
        results.sort(key=lambda x: (-int(x["is_over_budget"]), -x["percentage_used"]))
        return results

    @staticmethod
    def get_summary(db: Session, year: int, month: int) -> dict:
        """
        Summary: total budgeted, total spent across all categories, overall %.
        """
        progress = BudgetService.get_progress(db, year, month)
        total_budget = sum(p["budget_amount"] for p in progress)
        total_spent = sum(p["spent_amount"] for p in progress)
        over_count = sum(1 for p in progress if p["is_over_budget"])
        pct = round(total_spent / total_budget * 100, 1) if total_budget > 0 else 0.0

        return {
            "year": year,
            "month": month,
            "total_budgeted": total_budget,
            "total_spent": total_spent,
            "total_remaining": total_budget - total_spent,
            "overall_percentage": pct,
            "categories_count": len(progress),
            "over_budget_count": over_count,
            "categories": progress,
        }
