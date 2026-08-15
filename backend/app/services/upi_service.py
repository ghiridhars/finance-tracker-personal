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
    auto_categorize,
    extract_upi_id,
)

logger = logging.getLogger(__name__)


class UpiService:
    """Static-namespace service for the upi_ids table."""

    @staticmethod
    def get_unassigned_handles(db: Session, limit: int = 100) -> list[dict]:
        """
        Query all distinct UPI handles from UnifiedTransaction descriptions,
        filter out those already in upi_ids, and return a list of dicts.
        """
        txs = db.query(UnifiedTransaction).filter(
            UnifiedTransaction.description.like('%@%')
        ).all()

        existing_handles = {
            u[0] for u in db.query(UpiId.upi_handle).all()
        }

        handle_data = {}
        for tx in txs:
            if not tx.description:
                continue
            handle = extract_upi_id(tx.description)
            if handle:
                handle = handle.lower()
                if handle not in existing_handles:
                    if handle not in handle_data:
                        handle_data[handle] = {
                            "upi_handle": handle,
                            "transaction_count": 0,
                            "sample_description": tx.description,
                            "first_seen": tx.date.isoformat() if tx.date else None
                        }
                    handle_data[handle]["transaction_count"] += 1
                    if tx.date:
                        current_first = handle_data[handle]["first_seen"]
                        if current_first is None or tx.date.isoformat() < current_first:
                            handle_data[handle]["first_seen"] = tx.date.isoformat()
                            handle_data[handle]["sample_description"] = tx.description

        result = list(handle_data.values())
        result.sort(key=lambda x: x["transaction_count"], reverse=True)
        return result[:limit]

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
        upi_handle: str | None = ...,
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

        if upi_handle is not ... and upi_handle is not None:
            norm = upi_handle.strip().lower()
            existing = UpiService.get_by_handle(db, norm)
            if existing and existing.id != upi_id:
                db.delete(upi)
                db.commit()
                logger.info(
                    f"Auto-deleted duplicate UPI entry {upi_id} during edit. Original entry {existing.id} ({norm}) retained."
                )
                return existing
            upi.upi_handle = norm
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
            class_result, is_own_transfer = auto_categorize(
                db,
                description=tx.description,
                amount=tx.amount,
                bank_name=tx.bank,
                tx_type=tx.type.value if tx.type else None,
            )
            new_cat_id = None
            if class_result.confidence >= 0.85:
                new_cat_id = class_result.category_id

            changed = False

            # Update category if UPI/keyword match found and tx has no category
            # or if the new match is different
            if new_cat_id and tx.category_id != new_cat_id:
                tx.category_id = new_cat_id
                tx.classification_source = class_result.source
                tx.classification_confidence = class_result.confidence
                cat_updated += 1
                changed = True
                
            if class_result.category_id and tx.suggested_category_id != class_result.category_id:
                tx.suggested_category_id = class_result.category_id
                tx.classification_source = class_result.source
                tx.classification_confidence = class_result.confidence
                changed = True

            if class_result.merchant_name and tx.merchant_name != class_result.merchant_name:
                tx.merchant_name = class_result.merchant_name
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
