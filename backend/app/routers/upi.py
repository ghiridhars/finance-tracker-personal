"""
UPI ID management endpoints.

Manages UPI handle ↔ account/category mappings and provides
a rescan endpoint to retroactively apply UPI-based rules.
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.upi import UpiId
from app.schemas.upi import UpiIdSchema, UpiIdCreateSchema, UpiIdUpdateSchema
from app.services.upi_service import UpiService

router = APIRouter(prefix="/api/v2/upi-ids", tags=["UPI IDs"])


@router.get("/unassigned")
def list_unassigned_upi_handles(
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
):
    """List UPI handles seen in transactions but not yet in the upi_ids table."""
    result = UpiService.get_unassigned_handles(db, limit=limit)
    return result


@router.get("", response_model=list[UpiIdSchema])
def list_upi_ids(
    is_own: bool | None = Query(None, description="Filter by own vs third-party"),
    account_identifier: str | None = Query(None, description="Filter by account/card number"),
    db: Session = Depends(get_db),
):
    """List all UPI ID mappings, optionally filtered."""
    items = UpiService.list_all(db, is_own=is_own, account_identifier=account_identifier)
    return [UpiIdSchema.model_validate(u) for u in items]


@router.post("", response_model=UpiIdSchema, status_code=201)
def create_upi_id(data: UpiIdCreateSchema, db: Session = Depends(get_db)):
    """Create a new UPI ID mapping."""
    existing = UpiService.get_by_handle(db, data.upi_handle)
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"UPI handle '{data.upi_handle}' already exists",
        )
    upi = UpiService.create(
        db,
        upi_handle=data.upi_handle,
        label=data.label,
        account_type=data.account_type,
        account_identifier=data.account_identifier,
        category_id=data.category_id,
        is_own=data.is_own,
    )
    return UpiIdSchema.model_validate(upi)


@router.get("/{upi_id}", response_model=UpiIdSchema)
def get_upi_id(upi_id: int, db: Session = Depends(get_db)):
    """Get a single UPI ID mapping by ID."""
    upi = UpiService.get_by_id(db, upi_id)
    if not upi:
        raise HTTPException(status_code=404, detail="UPI ID not found")
    return UpiIdSchema.model_validate(upi)


@router.put("/{upi_id}", response_model=UpiIdSchema)
def update_upi_id(upi_id: int, data: UpiIdUpdateSchema, db: Session = Depends(get_db)):
    """Update an existing UPI ID mapping."""
    upi = UpiService.update(
        db,
        upi_id,
        upi_handle=data.upi_handle if data.upi_handle is not None else ...,
        label=data.label if data.label is not None else ...,
        account_type=data.account_type if data.account_type is not None else ...,
        account_identifier=data.account_identifier if data.account_identifier is not None else ...,
        category_id=data.category_id if data.category_id is not None else ...,
        is_own=data.is_own,
    )
    if not upi:
        raise HTTPException(status_code=404, detail="UPI ID not found")
    return UpiIdSchema.model_validate(upi)


@router.delete("/{upi_id}")
def delete_upi_id(upi_id: int, db: Session = Depends(get_db)):
    """Delete a UPI ID mapping."""
    if not UpiService.delete(db, upi_id):
        raise HTTPException(status_code=404, detail="UPI ID not found")
    return {"detail": "Deleted"}


@router.post("/rescan")
def rescan_transactions(db: Session = Depends(get_db)):
    """
    Re-scan all existing transactions against current UPI-based rules.
    Updates categories and transfer flags based on UPI handle matches.
    """
    result = UpiService.rescan_transactions(db)
    return result
