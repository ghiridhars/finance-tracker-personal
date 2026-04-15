"""
Savings Goals service — CRUD + progress tracking.
"""
import logging
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models.budget import SavingsGoal

logger = logging.getLogger(__name__)


class SavingsGoalService:
    """Savings goal CRUD with progress computation."""

    @staticmethod
    def create(db: Session, *, name: str, target_amount: Decimal,
               current_amount: Decimal = Decimal("0"),
               deadline: date | None = None,
               icon: str | None = None, color: str | None = None,
               notes: str | None = None) -> SavingsGoal:
        goal = SavingsGoal(
            name=name, target_amount=target_amount,
            current_amount=current_amount, deadline=deadline,
            icon=icon, color=color, notes=notes,
        )
        db.add(goal)
        db.commit()
        db.refresh(goal)
        logger.info(f"Created savings goal id={goal.id} name='{name}' target={target_amount}")
        return goal

    @staticmethod
    def update(db: Session, goal_id: int, **kwargs) -> SavingsGoal | None:
        goal = db.query(SavingsGoal).filter(SavingsGoal.id == goal_id).first()
        if not goal:
            return None
        for k, v in kwargs.items():
            if v is not None and hasattr(goal, k):
                setattr(goal, k, v)
        # Auto-complete if current >= target
        if goal.current_amount >= goal.target_amount:
            goal.is_completed = True
        db.commit()
        db.refresh(goal)
        return goal

    @staticmethod
    def contribute(db: Session, goal_id: int, amount: Decimal) -> SavingsGoal | None:
        """Add a contribution to a savings goal."""
        goal = db.query(SavingsGoal).filter(SavingsGoal.id == goal_id).first()
        if not goal:
            return None
        goal.current_amount += amount
        if goal.current_amount >= goal.target_amount:
            goal.is_completed = True
        db.commit()
        db.refresh(goal)
        logger.info(f"Contributed {amount} to goal id={goal_id}, now at {goal.current_amount}")
        return goal

    @staticmethod
    def delete(db: Session, goal_id: int) -> bool:
        goal = db.query(SavingsGoal).filter(SavingsGoal.id == goal_id).first()
        if not goal:
            return False
        db.delete(goal)
        db.commit()
        return True

    @staticmethod
    def get_by_id(db: Session, goal_id: int) -> SavingsGoal | None:
        return db.query(SavingsGoal).filter(SavingsGoal.id == goal_id).first()

    @staticmethod
    def get_by_id_with_progress(db: Session, goal_id: int) -> dict | None:
        """Get a single goal with computed progress fields."""
        goal = db.query(SavingsGoal).filter(SavingsGoal.id == goal_id).first()
        if not goal:
            return None
        today = date.today()
        pct = float(goal.current_amount / goal.target_amount * 100) if goal.target_amount > 0 else 0.0
        days_remaining = (goal.deadline - today).days if goal.deadline else None
        return {
            "id": goal.id,
            "name": goal.name,
            "target_amount": float(goal.target_amount),
            "current_amount": float(goal.current_amount),
            "deadline": goal.deadline.isoformat() if goal.deadline else None,
            "icon": goal.icon,
            "color": goal.color,
            "notes": goal.notes,
            "is_completed": goal.is_completed,
            "created_at": goal.created_at.isoformat() if goal.created_at else None,
            "percentage": round(min(pct, 100.0), 1),
            "days_remaining": days_remaining,
        }

    @staticmethod
    def list_goals(db: Session, include_completed: bool = True) -> list[dict]:
        """List all goals with computed progress fields."""
        q = db.query(SavingsGoal)
        if not include_completed:
            q = q.filter(SavingsGoal.is_completed == False)
        goals = q.order_by(SavingsGoal.deadline.asc().nullslast()).all()

        results = []
        today = date.today()
        for g in goals:
            pct = float(g.current_amount / g.target_amount * 100) if g.target_amount > 0 else 0.0
            days_remaining = (g.deadline - today).days if g.deadline else None

            results.append({
                "id": g.id,
                "name": g.name,
                "target_amount": float(g.target_amount),
                "current_amount": float(g.current_amount),
                "deadline": g.deadline.isoformat() if g.deadline else None,
                "icon": g.icon,
                "color": g.color,
                "notes": g.notes,
                "is_completed": g.is_completed,
                "created_at": g.created_at.isoformat() if g.created_at else None,
                "percentage": round(min(pct, 100.0), 1),
                "days_remaining": days_remaining,
            })

        return results
