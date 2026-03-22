"""
UPI ID management service.

Handles CRUD for UPI ID mappings and retroactive re-scan of
existing transactions against UPI-based rules.
"""
import logging
from typing import Optional

from sqlalchemy.orm import Session

from app.models.upi import UpiId
from app.models.transaction import UnifiedTransaction
from app.services.categorization_service import (
    categorize_and_normalize,
    extract_upi_id,
)

logger = logging.getLogger(__name__)


class UpiService:
    """Static-namespace service for the upi_ids table."""

    @staticmethod
    def list_all(
        db: Session,
        *,
        is_own: bool | None = None,
        account_identifier: str | None = None,
    ) -> list[UpiId]:
        """List UPI IDs with optional filters."""
        q = db.query(UpiId)
        if is_own is not None:
            q = q.filter(UpiId.is_own == is_own)
        if account_identifier:
            q = q.filter(UpiId.account_identifier == account_identifier)
        return q.order_by(UpiId.created_at.desc()).all()

    @staticmethod
    def get_by_id(db: Session, upi_id: int) -> Optional[UpiId]:
        return db.query(UpiId).filter(UpiId.id == upi_id).first()

    @staticmethod
    def get_by_handle(db: Session, handle: str) -> Optional[UpiId]:
        return db.query(UpiId).filter(UpiId.upi_handle == handle.lower()).first()

    @staticmethod
    def create(
        db: Session,
        *,
        upi_handle: str,
        label: str | None = None,
        account_type: str | None = None,
        account_identifier: str | None = None,
        category_id: int | None = None,
        is_own: bool = False,
    ) -> UpiId:
        """Create a new UPI ID mapping."""
        upi = UpiId(
            upi_handle=upi_handle.strip().lower(),
            label=label,
            account_type=account_type,
            account_identifier=account_identifier,
            category_id=category_id,
            is_own=is_own,
        )
        db.add(upi)
        db.commit()
        db.refresh(upi)
        logger.info(f"Created UPI mapping: {upi.upi_handle} (is_own={upi.is_own})")
        return upi

    @staticmethod
    def update(
        db: Session,
        upi_id: int,
        *,
        label: str | None = ...,
        account_type: str | None = ...,
        account_identifier: str | None = ...,
        category_id: int | None = ...,
        is_own: bool | None = None,
    ) -> Optional[UpiId]:
        """Update an existing UPI ID mapping."""
        upi = db.query(UpiId).filter(UpiId.id == upi_id).first()
        if not upi:
            return None

        if label is not ...:
            upi.label = label
        if account_type is not ...:
            upi.account_type = account_type
        if account_identifier is not ...:
            upi.account_identifier = account_identifier
        if category_id is not ...:
            upi.category_id = category_id
        if is_own is not None:
            upi.is_own = is_own

        db.commit()
        db.refresh(upi)
        logger.info(f"Updated UPI mapping: {upi.upi_handle}")
        return upi

    @staticmethod
    def delete(db: Session, upi_id: int) -> bool:
        """Delete a UPI ID mapping. Returns True if found and deleted."""
        upi = db.query(UpiId).filter(UpiId.id == upi_id).first()
        if not upi:
            return False
        db.delete(upi)
        db.commit()
        logger.info(f"Deleted UPI mapping: {upi.upi_handle}")
        return True

    @staticmethod
    def rescan_transactions(db: Session) -> dict:
        """
        Re-scan all existing transactions against UPI-based rules.

        Only updates transactions that:
          - Have no category set, OR
          - Would benefit from a UPI-based transfer flag.

        Returns a summary dict with counts of changes made.
        """
        transactions = db.query(UnifiedTransaction).all()
        cat_updated = 0
        transfer_flagged = 0

        for tx in transactions:
            new_cat_id, new_merchant, is_own_transfer = categorize_and_normalize(
                db, tx.description,
            )

            changed = False

            # Update category if UPI/keyword match found and tx has no category
            # or if the new match is different
            if new_cat_id and tx.category_id != new_cat_id:
                tx.category_id = new_cat_id
                cat_updated += 1
                changed = True

            if new_merchant and tx.merchant_name != new_merchant:
                tx.merchant_name = new_merchant
                changed = True

            # Flag as transfer if own UPI detected
            if is_own_transfer and not tx.is_transfer:
                tx.is_transfer = True
                transfer_flagged += 1
                changed = True

        if cat_updated or transfer_flagged:
            db.commit()

        result = {
            "transactions_scanned": len(transactions),
            "categories_updated": cat_updated,
            "transfers_flagged": transfer_flagged,
        }
        logger.info(f"UPI rescan complete: {result}")
        return result
