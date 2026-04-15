"""
Transfer management endpoints — detect, link, unlink, and list
inter-account transfers and CC bill payments.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.transaction import (
    TransferDetectResult,
    TransferLinkRequest,
    TransferPairSchema,
    UnifiedTransactionSchema,
)
from app.services.transfer_detection_service import TransferDetectionService

router = APIRouter(prefix="/api/v2/transfers", tags=["Transfers"])


@router.post("/detect", response_model=TransferDetectResult)
def detect_transfers(db: Session = Depends(get_db)):
    """Run auto-detection on all unlinked transactions."""
    pairs = TransferDetectionService.detect_all(db)
    return TransferDetectResult(
        linked_count=len(pairs),
        details=[
            TransferPairSchema(
                transfer_group_id=p["transfer_group_id"],
                transfer_type=p["transfer_type"],
                transactions=[],  # lightweight response; caller can GET /transfers for full detail
            )
            for p in pairs
        ],
    )


@router.post("/link", response_model=TransferPairSchema)
def link_transfer(
    body: TransferLinkRequest,
    db: Session = Depends(get_db),
):
    """Manually link two transactions as a transfer pair."""
    group_id = TransferDetectionService.link_manual(
        db,
        body.transaction_id_1,
        body.transaction_id_2,
        body.transfer_type,
    )
    if not group_id:
        raise HTTPException(status_code=404, detail="One or both transactions not found")

    # Fetch the linked pair for the response
    pair = _get_pair_or_404(db, group_id)
    return pair


@router.delete("/{transfer_group_id}")
def unlink_transfer(transfer_group_id: str, db: Session = Depends(get_db)):
    """Unlink a transfer pair."""
    success = TransferDetectionService.unlink(db, transfer_group_id)
    if not success:
        raise HTTPException(status_code=404, detail="Transfer pair not found")
    return {"message": "Transfer pair unlinked", "transfer_group_id": transfer_group_id}


@router.get("/", response_model=list[TransferPairSchema])
def list_transfers(db: Session = Depends(get_db)):
    """List all linked transfer pairs."""
    raw_pairs = TransferDetectionService.list_pairs(db)
    return [
        TransferPairSchema(
            transfer_group_id=p["transfer_group_id"],
            transfer_type=p["transfer_type"],
            transactions=[
                UnifiedTransactionSchema.model_validate(tx) for tx in p["transactions"]
            ],
        )
        for p in raw_pairs
    ]


@router.patch("/{transfer_group_id}", response_model=TransferPairSchema)
def update_transfer_type(
    transfer_group_id: str,
    transfer_type: str,
    db: Session = Depends(get_db),
):
    """Update the transfer type for a linked pair."""
    from app.models.enums import TransferType

    try:
        new_type = TransferType(transfer_type)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid transfer_type. Must be one of: {[t.value for t in TransferType]}",
        )

    txns = TransferDetectionService.update_transfer_type(db, transfer_group_id, new_type)
    if not txns:
        raise HTTPException(status_code=404, detail="Transfer pair not found")

    return TransferPairSchema(
        transfer_group_id=transfer_group_id,
        transfer_type=new_type,
        transactions=[UnifiedTransactionSchema.model_validate(tx) for tx in txns],
    )


# ── Helpers ──────────────────────────────────────────────────

def _get_pair_or_404(db: Session, transfer_group_id: str) -> TransferPairSchema:
    from app.models.transaction import UnifiedTransaction

    txns = (
        db.query(UnifiedTransaction)
        .filter(UnifiedTransaction.transfer_group_id == transfer_group_id)
        .all()
    )
    if not txns:
        raise HTTPException(status_code=404, detail="Transfer pair not found")

    return TransferPairSchema(
        transfer_group_id=transfer_group_id,
        transfer_type=txns[0].transfer_type,
        transactions=[UnifiedTransactionSchema.model_validate(tx) for tx in txns],
    )
