"""
Bill Reminders & Recurring Transactions router.

Endpoints:
  Bill Reminders:
  - GET    /api/v2/reminders              — List reminders (with overdue/upcoming)
  - POST   /api/v2/reminders              — Create reminder
  - PATCH  /api/v2/reminders/{id}         — Update reminder
  - POST   /api/v2/reminders/{id}/paid    — Mark as paid (auto-advance if recurring)
  - DELETE /api/v2/reminders/{id}         — Delete reminder
  - POST   /api/v2/reminders/auto-detect  — Auto-detect CC due dates

  Recurring Transactions:
  - GET    /api/v2/recurring              — List detected recurring patterns
  - POST   /api/v2/recurring/detect       — Run detection algorithm
  - PATCH  /api/v2/recurring/{id}/subscription — Toggle subscription flag
  - DELETE /api/v2/recurring/{id}         — Delete / deactivate pattern
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.bill_reminder_service import BillReminderService
from app.services.recurring_service import RecurringDetectionService
from app.schemas.budget import (
    BillReminderCreate, BillReminderUpdate, RecurringTransactionSchema,
)

router = APIRouter(tags=["Reminders & Recurring"])

# ──────────────────────────────────────────────────────────────
# Bill Reminders
# ──────────────────────────────────────────────────────────────


@router.get("/api/v2/reminders")
def list_reminders(
    include_paid: bool = Query(False),
    upcoming_days: int = Query(None),
    db: Session = Depends(get_db),
):
    """List bill reminders, optionally filtering to upcoming N days."""
    return BillReminderService.list_reminders(
        db, include_paid=include_paid, upcoming_days=upcoming_days,
    )


@router.post("/api/v2/reminders")
def create_reminder(data: BillReminderCreate, db: Session = Depends(get_db)):
    reminder = BillReminderService.create(
        db,
        name=data.name,
        amount=data.amount,
        category_id=data.category_id,
        is_recurring=data.is_recurring,
        frequency=data.frequency,
        day_of_month=data.day_of_month,
        next_due_date=data.next_due_date,
        notes=data.notes,
    )
    return BillReminderService.list_reminders(db)


@router.patch("/api/v2/reminders/{reminder_id}")
def update_reminder(reminder_id: int, data: BillReminderUpdate, db: Session = Depends(get_db)):
    kwargs = {k: v for k, v in data.model_dump().items() if v is not None}
    reminder = BillReminderService.update(db, reminder_id, **kwargs)
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    return BillReminderService.list_reminders(db)


@router.post("/api/v2/reminders/{reminder_id}/paid")
def mark_paid(reminder_id: int, db: Session = Depends(get_db)):
    """Mark a bill as paid. Recurring bills advance to next due date automatically."""
    reminder = BillReminderService.mark_paid(db, reminder_id)
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    return {"detail": "Marked as paid", "id": reminder_id}


@router.delete("/api/v2/reminders/{reminder_id}")
def delete_reminder(reminder_id: int, db: Session = Depends(get_db)):
    if not BillReminderService.delete(db, reminder_id):
        raise HTTPException(status_code=404, detail="Reminder not found")
    return {"detail": "Reminder deleted", "id": reminder_id}


@router.post("/api/v2/reminders/auto-detect")
def auto_detect_reminders(db: Session = Depends(get_db)):
    """Auto-create bill reminders from CC statement due dates."""
    created = BillReminderService.auto_detect_cc_dues(db)
    return {"detected": len(created)}


# ──────────────────────────────────────────────────────────────
# Recurring Transactions
# ──────────────────────────────────────────────────────────────


@router.get("/api/v2/recurring")
def list_recurring(
    active_only: bool = Query(True),
    db: Session = Depends(get_db),
):
    """List detected recurring transaction patterns."""
    items = RecurringDetectionService.list_recurring(db, active_only=active_only)
    return [RecurringTransactionSchema.model_validate(r) for r in items]


@router.post("/api/v2/recurring/detect")
def detect_recurring(db: Session = Depends(get_db)):
    """Run the recurring transaction detection algorithm."""
    created = RecurringDetectionService.detect(db)
    return {
        "detected": len(created),
        "items": [RecurringTransactionSchema.model_validate(r) for r in created],
    }


@router.patch("/api/v2/recurring/{recurring_id}/subscription")
def toggle_subscription(
    recurring_id: int,
    is_subscription: bool = Query(...),
    db: Session = Depends(get_db),
):
    """Mark/unmark a recurring transaction as a subscription."""
    rec = RecurringDetectionService.toggle_subscription(db, recurring_id, is_subscription)
    if not rec:
        raise HTTPException(status_code=404, detail="Recurring pattern not found")
    return RecurringTransactionSchema.model_validate(rec)


@router.delete("/api/v2/recurring/{recurring_id}")
def delete_recurring(recurring_id: int, db: Session = Depends(get_db)):
    if not RecurringDetectionService.delete(db, recurring_id):
        raise HTTPException(status_code=404, detail="Recurring pattern not found")
    return {"detail": "Pattern deleted", "id": recurring_id}
