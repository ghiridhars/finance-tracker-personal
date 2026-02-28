"""
Health check endpoint.
Replaces: HealthController.java + HealthService.java + HealthServiceImpl.java
"""
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db

router = APIRouter(tags=["Health"])


@router.get("/health")
def health_check(db: Session = Depends(get_db)):
    """
    Replaces: HealthController.health() + HealthServiceImpl.isDatabaseUp()

    Checks if the database connection is valid.
    """
    try:
        db.execute(text("SELECT 1"))
        return {"status": "UP", "database": True}
    except Exception:
        return {"status": "DOWN", "database": False}
