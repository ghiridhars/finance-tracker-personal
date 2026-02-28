"""
Savings Goals router.

Endpoints:
  - GET    /api/v2/goals                — List all goals with progress
  - GET    /api/v2/goals/{id}           — Get single goal
  - POST   /api/v2/goals                — Create goal
  - PATCH  /api/v2/goals/{id}           — Update goal
  - POST   /api/v2/goals/{id}/contribute — Add contribution
  - DELETE /api/v2/goals/{id}           — Delete goal
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.goals_service import SavingsGoalService
from app.schemas.budget import SavingsGoalCreate, SavingsGoalUpdate

router = APIRouter(prefix="/api/v2/goals", tags=["Savings Goals"])


@router.get("")
def list_goals(
    include_completed: bool = Query(True),
    db: Session = Depends(get_db),
):
    """List all savings goals with computed progress."""
    return SavingsGoalService.list_goals(db, include_completed=include_completed)


@router.get("/{goal_id}")
def get_goal(goal_id: int, db: Session = Depends(get_db)):
    goal = SavingsGoalService.get_by_id(db, goal_id)
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    # Return as dict with progress
    goals = SavingsGoalService.list_goals(db)
    match = next((g for g in goals if g["id"] == goal_id), None)
    return match or goal


@router.post("")
def create_goal(data: SavingsGoalCreate, db: Session = Depends(get_db)):
    goal = SavingsGoalService.create(
        db,
        name=data.name,
        target_amount=data.target_amount,
        current_amount=data.current_amount,
        deadline=data.deadline,
        icon=data.icon,
        color=data.color,
        notes=data.notes,
    )
    return SavingsGoalService.list_goals(db)[-1]  # Return with computed fields


@router.patch("/{goal_id}")
def update_goal(goal_id: int, data: SavingsGoalUpdate, db: Session = Depends(get_db)):
    kwargs = {k: v for k, v in data.model_dump().items() if v is not None}
    goal = SavingsGoalService.update(db, goal_id, **kwargs)
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    goals = SavingsGoalService.list_goals(db)
    return next((g for g in goals if g["id"] == goal_id), None)


@router.post("/{goal_id}/contribute")
def contribute(goal_id: int, amount: float = Query(..., gt=0), db: Session = Depends(get_db)):
    """Add a contribution to a savings goal."""
    from decimal import Decimal
    goal = SavingsGoalService.contribute(db, goal_id, Decimal(str(amount)))
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    goals = SavingsGoalService.list_goals(db)
    return next((g for g in goals if g["id"] == goal_id), None)


@router.delete("/{goal_id}")
def delete_goal(goal_id: int, db: Session = Depends(get_db)):
    if not SavingsGoalService.delete(db, goal_id):
        raise HTTPException(status_code=404, detail="Goal not found")
    return {"detail": "Goal deleted", "id": goal_id}
