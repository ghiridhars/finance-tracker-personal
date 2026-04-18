"""
Bill Reminder service — CRUD + auto-detection from CC due dates + overdue tracking.
"""
import logging
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy.orm import Session

from app.models.budget import BillReminder
from app.models.statement_audit import StatementAudit

logger = logging.getLogger(__name__)


class BillReminderService:
    """Bill reminders — manual + auto-detected from CC statements."""

    # ── CRUD ─────────────────────────────────────────────

    @staticmethod
    def create(db: Session, *, name: str, amount: Decimal | None = None,
               category_id: int | None = None, is_recurring: bool = True,
               frequency: str | None = None, day_of_month: int | None = None,
               next_due_date: date | None = None, notes: str | None = None) -> BillReminder:
        reminder = BillReminder(
            name=name, amount=amount, category_id=category_id,
            is_recurring=is_recurring, frequency=frequency,
            day_of_month=day_of_month, next_due_date=next_due_date,
            notes=notes,
        )
        db.add(reminder)
        db.commit()
        db.refresh(reminder)
        logger.info(f"Created bill reminder id={reminder.id} name='{name}' due={next_due_date}")
        return reminder

    @staticmethod
    def update(db: Session, reminder_id: int, **kwargs) -> BillReminder | None:
        reminder = db.query(BillReminder).filter(BillReminder.id == reminder_id).first()
        if not reminder:
            return None
        for k, v in kwargs.items():
            if v is not None and hasattr(reminder, k):
                setattr(reminder, k, v)
        db.commit()
        db.refresh(reminder)
        return reminder

    @staticmethod
    def mark_paid(db: Session, reminder_id: int) -> BillReminder | None:
        """Mark a reminder as paid and advance next_due_date if recurring."""
        reminder = db.query(BillReminder).filter(BillReminder.id == reminder_id).first()
        if not reminder:
            return None

        reminder.is_paid = True

        # Advance due date for recurring bills
        if reminder.is_recurring and reminder.next_due_date:
            freq = (reminder.frequency or "MONTHLY").upper()
            if freq == "MONTHLY":
                reminder.next_due_date = _advance_month(reminder.next_due_date, 1)
            elif freq == "QUARTERLY":
                reminder.next_due_date = _advance_month(reminder.next_due_date, 3)
            elif freq == "YEARLY":
                reminder.next_due_date = _advance_month(reminder.next_due_date, 12)
            reminder.is_paid = False  # Reset for next cycle

        db.commit()
        db.refresh(reminder)
        return reminder

    @staticmethod
    def delete(db: Session, reminder_id: int) -> bool:
        reminder = db.query(BillReminder).filter(BillReminder.id == reminder_id).first()
        if not reminder:
            return False
        db.delete(reminder)
        db.commit()
        return True

    # ── List & query ─────────────────────────────────────

    @staticmethod
    def list_reminders(db: Session, include_paid: bool = False,
                       upcoming_days: int | None = None) -> list[dict]:
        """
        List bill reminders with computed fields (days_until_due, is_overdue).
        Optionally filter to only upcoming within N days.
        """
        q = db.query(BillReminder)
        if not include_paid:
            q = q.filter(BillReminder.is_paid == False)

        reminders = q.order_by(BillReminder.next_due_date.asc().nullslast()).all()
        today = date.today()
        results = []

        for r in reminders:
            days_until = (r.next_due_date - today).days if r.next_due_date else None
            is_overdue = days_until is not None and days_until < 0

            if upcoming_days is not None and days_until is not None:
                if days_until > upcoming_days:
                    continue

            results.append({
                "id": r.id,
                "name": r.name,
                "amount": float(r.amount) if r.amount else None,
                "category_id": r.category_id,
                "category": {
                    "id": r.category.id,
                    "name": r.category.name,
                    "color": r.category.color,
                    "icon": r.category.icon,
                } if r.category else None,
                "is_recurring": r.is_recurring,
                "frequency": r.frequency,
                "day_of_month": r.day_of_month,
                "next_due_date": r.next_due_date.isoformat() if r.next_due_date else None,
                "is_auto_detected": r.is_auto_detected,
                "is_paid": r.is_paid,
                "notes": r.notes,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "days_until_due": days_until,
                "is_overdue": is_overdue,
            })

        return results

    # ── Auto-detect from CC statements ───────────────────

    @staticmethod
    def auto_detect_cc_dues(db: Session) -> list[BillReminder]:
        """
        Create bill reminders from credit card statement due dates.
        One reminder per card (latest statement's due date).
        """
        from sqlalchemy import func

        # Get latest CC statement audit per card_number
        subq = (
            db.query(
                StatementAudit.card_number,
                func.max(StatementAudit.period_start).label("max_date"),
            )
            .filter(
                StatementAudit.statement_type == "CREDIT_CARD",
                StatementAudit.status == "SUCCESS",
                StatementAudit.card_number.isnot(None),
            )
            .group_by(StatementAudit.card_number)
            .subquery()
        )

        latest_stmts = (
            db.query(StatementAudit)
            .join(
                subq,
                (StatementAudit.card_number == subq.c.card_number)
                & (StatementAudit.period_start == subq.c.max_date),
            )
            .all()
        )

        created = []
        for stmt in latest_stmts:
            if not stmt.due_date:
                continue

            card_last4 = stmt.card_number[-4:] if stmt.card_number and len(stmt.card_number) >= 4 else stmt.card_number

            # Check if already exists
            existing = (
                db.query(BillReminder)
                .filter(
                    BillReminder.name.ilike(f"%{card_last4}%"),
                    BillReminder.is_auto_detected == True,
                )
                .first()
            )
            if existing:
                # Update due date and amount
                existing.next_due_date = stmt.due_date
                existing.amount = stmt.minimum_amount_due or stmt.closing_balance
                continue

            reminder = BillReminder(
                name=f"CC Payment ****{card_last4}",
                amount=stmt.minimum_amount_due or stmt.closing_balance,
                is_recurring=True,
                frequency="MONTHLY",
                day_of_month=stmt.due_date.day if stmt.due_date else None,
                next_due_date=stmt.due_date,
                is_auto_detected=True,
                notes=f"Auto-detected from credit card statement. Total dues: {stmt.closing_balance}",
            )
            db.add(reminder)
            created.append(reminder)

        db.commit()
        for r in created:
            db.refresh(r)

        logger.info(f"Auto-detected {len(created)} CC bill reminders")
        return created


def _advance_month(d: date, months: int) -> date:
    """Advance a date by N months, clamping day to month end."""
    month = d.month - 1 + months
    year = d.year + month // 12
    month = month % 12 + 1
    import calendar
    max_day = calendar.monthrange(year, month)[1]
    day = min(d.day, max_day)
    return date(year, month, day)
