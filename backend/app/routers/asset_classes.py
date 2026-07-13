from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models.asset_class import AssetClass
from app.schemas.asset_class import AssetClassCreate, AssetClassUpdate, AssetClassResponse

router = APIRouter(prefix="/api/v2/asset-classes", tags=["Asset Classes"])

@router.get("", response_model=List[AssetClassResponse])
def get_asset_classes(db: Session = Depends(get_db)):
    return db.query(AssetClass).all()

@router.post("", response_model=AssetClassResponse, status_code=201)
def create_asset_class(item: AssetClassCreate, db: Session = Depends(get_db)):
    db_item = AssetClass(**item.model_dump())
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

@router.put("/{item_id}", response_model=AssetClassResponse)
def update_asset_class(item_id: int, item: AssetClassUpdate, db: Session = Depends(get_db)):
    db_item = db.query(AssetClass).filter(AssetClass.id == item_id).first()
    if not db_item:
        raise HTTPException(status_code=404, detail="Asset class not found")
    
    update_data = item.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        setattr(db_item, k, v)
    
    db.commit()
    db.refresh(db_item)
    return db_item

@router.delete("/{item_id}", status_code=204)
def delete_asset_class(item_id: int, db: Session = Depends(get_db)):
    db_item = db.query(AssetClass).filter(AssetClass.id == item_id).first()
    if not db_item:
        raise HTTPException(status_code=404, detail="Asset class not found")
    db.delete(db_item)
    db.commit()
