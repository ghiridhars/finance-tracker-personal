"""
Recurring Transaction detection service.

Analyses unified transactions to find patterns:
  - Same merchant appearing regularly (monthly/weekly)
  - Similar amounts across occurrences
  - Creates RecurringTransaction entries for detected patterns
"""
import logging
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from statistics import mean, stdev
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.budget import RecurringTransaction
from app.models.transaction import UnifiedTransaction
from app.models.enums import TransactionType

logger = logging.getLogger(__name__)


class RecurringDetectionService:
    """Auto-detect recurring transactions from historical data."""

    # Thresholds for detection
    MIN_OCCURRENCES = 3         # Need at least 3 matches
    MAX_AMOUNT_VARIANCE = 0.20  # 20% variance in amount allowed
    MAX_INTERVAL_VARIANCE = 0.30  # 30% variance in interval allowed

    @staticmethod
    def detect(db: Session) -> list[RecurringTransaction]:
        """
        Scan all DEBIT transactions, group by merchant, detect recurring patterns.
        Returns newly created RecurringTransaction entries.
        """
        # Get all debit transactions with a merchant name, ordered by date
        txns = (
            db.query(UnifiedTransaction)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.merchant_name.isnot(None),
                UnifiedTransaction.merchant_name != "",
                UnifiedTransaction.date.isnot(None),
            )
            .order_by(UnifiedTransaction.merchant_name, UnifiedTransaction.date)
            .all()
        )

        # Group by merchant
        by_merchant: dict[str, list[UnifiedTransaction]] = defaultdict(list)
        for tx in txns:
            key = tx.merchant_name.strip().lower()
            by_merchant[key].append(tx)

        created = []
        for merchant_key, merchant_txns in by_merchant.items():
            if len(merchant_txns) < RecurringDetectionService.MIN_OCCURRENCES:
                continue

            result = RecurringDetectionService._analyze_pattern(merchant_txns)
            if not result:
                continue

            # Check if we already have this pattern
            existing = (
                db.query(RecurringTransaction)
                .filter(
                    func.lower(RecurringTransaction.merchant_name) == merchant_key
                )
                .first()
            )
            if existing:
                # Update existing
                existing.average_amount = result["average_amount"]
                existing.frequency = result["frequency"]
                existing.last_date = result["last_date"]
                existing.next_expected_date = result["next_expected_date"]
                existing.occurrence_count = result["occurrence_count"]
                existing.category_id = result["category_id"]
                existing.description_pattern = result["description_pattern"]
                continue

            rec = RecurringTransaction(
                merchant_name=merchant_txns[0].merchant_name,  # Original casing
                description_pattern=result["description_pattern"],
                average_amount=result["average_amount"],
                frequency=result["frequency"],
                category_id=result["category_id"],
                last_date=result["last_date"],
                next_expected_date=result["next_expected_date"],
                occurrence_count=result["occurrence_count"],
                is_active=True,
            )
            db.add(rec)
            created.append(rec)

        db.commit()
        for r in created:
            db.refresh(r)

        logger.info(f"Recurring detection: found {len(created)} new patterns")
        return created

    @staticmethod
    def _analyze_pattern(txns: list[UnifiedTransaction]) -> Optional[dict]:
        """
        Analyze a list of transactions for the same merchant.
        Returns pattern dict or None if no recurring pattern detected.
        """
        amounts = [float(tx.amount) for tx in txns if tx.amount]
        dates = sorted([tx.date for tx in txns if tx.date])

        if len(dates) < RecurringDetectionService.MIN_OCCURRENCES:
            return None
        if len(amounts) < RecurringDetectionService.MIN_OCCURRENCES:
            return None

        # Check amount consistency
        avg_amount = mean(amounts)
        if avg_amount == 0:
            return None
        if len(amounts) > 1:
            amount_std = stdev(amounts)
            amount_cv = amount_std / avg_amount  # Coefficient of variation
            if amount_cv > RecurringDetectionService.MAX_AMOUNT_VARIANCE:
                return None

        # Check interval consistency
        intervals = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
        if not intervals:
            return None

        avg_interval = mean(intervals)
        if avg_interval == 0:
            return None

        if len(intervals) > 1:
            interval_std = stdev(intervals)
            interval_cv = interval_std / avg_interval
            if interval_cv > RecurringDetectionService.MAX_INTERVAL_VARIANCE:
                return None

        # Determine frequency
        frequency = RecurringDetectionService._classify_frequency(avg_interval)
        if not frequency:
            return None

        # Next expected date
        last_date = dates[-1]
        next_date = last_date + timedelta(days=int(avg_interval))

        # Most common category
        cat_ids = [tx.category_id for tx in txns if tx.category_id]
        category_id = max(set(cat_ids), key=cat_ids.count) if cat_ids else None

        # Description pattern (most common description)
        descriptions = [tx.description for tx in txns if tx.description]
        desc_pattern = max(set(descriptions), key=descriptions.count) if descriptions else None

        return {
            "average_amount": Decimal(str(round(avg_amount, 2))),
            "frequency": frequency,
            "last_date": last_date,
            "next_expected_date": next_date,
            "occurrence_count": len(dates),
            "category_id": category_id,
            "description_pattern": desc_pattern,
        }

    @staticmethod
    def _classify_frequency(avg_interval_days: float) -> Optional[str]:
        """Map average interval to frequency label."""
        if 5 <= avg_interval_days <= 10:
            return "WEEKLY"
        if 25 <= avg_interval_days <= 35:
            return "MONTHLY"
        if 80 <= avg_interval_days <= 100:
            return "QUARTERLY"
        if 350 <= avg_interval_days <= 380:
            return "YEARLY"
        return None  # No recognizable pattern

    # ── CRUD ─────────────────────────────────────────────

    @staticmethod
    def list_recurring(db: Session, active_only: bool = True) -> list[RecurringTransaction]:
        q = db.query(RecurringTransaction)
        if active_only:
            q = q.filter(RecurringTransaction.is_active == True)
        return q.order_by(RecurringTransaction.next_expected_date).all()

    @staticmethod
    def toggle_subscription(db: Session, recurring_id: int, is_subscription: bool) -> RecurringTransaction | None:
        rec = db.query(RecurringTransaction).filter(RecurringTransaction.id == recurring_id).first()
        if not rec:
            return None
        rec.is_subscription = is_subscription
        db.commit()
        db.refresh(rec)
        return rec

    @staticmethod
    def delete(db: Session, recurring_id: int) -> bool:
        rec = db.query(RecurringTransaction).filter(RecurringTransaction.id == recurring_id).first()
        if not rec:
            return False
        db.delete(rec)
        db.commit()
        return True
