"""
Category CRUD endpoints.
"""
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.category_service import CategoryService
from app.models.category import MccCategory
from app.schemas.category import (
    CategorySchema,
    CategoryCreateSchema,
    CategoryUpdateSchema,
    MccCategorySchema,
    KeywordAddSchema,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v2/categories", tags=["Categories"])


@router.get("", response_model=list[CategorySchema])
def list_categories(db: Session = Depends(get_db)):
    """List all top-level categories with their keywords."""
    return [CategorySchema.model_validate(c) for c in CategoryService.get_all(db)]


@router.get("/mcc", response_model=list[MccCategorySchema])
def list_mcc_codes(db: Session = Depends(get_db)):
    """List all MCC codes and their mapped categories."""
    mccs = db.query(MccCategory).order_by(MccCategory.mcc_code).all()
    return [MccCategorySchema.model_validate(mcc) for mcc in mccs]


@router.get("/{category_id}", response_model=CategorySchema)
def get_category(category_id: int, db: Session = Depends(get_db)):
    cat = CategoryService.get_by_id(db, category_id)
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")
    return CategorySchema.model_validate(cat)


@router.post("", response_model=CategorySchema, status_code=201)
def create_category(data: CategoryCreateSchema, db: Session = Depends(get_db)):
    try:
        cat = CategoryService.create(db, data)
        return CategorySchema.model_validate(cat)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{category_id}/keywords", response_model=CategorySchema)
def add_keywords(category_id: int, data: KeywordAddSchema, db: Session = Depends(get_db)):
    try:
        cat = CategoryService.add_keywords(db, category_id, data.keywords)
        return CategorySchema.model_validate(cat)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/keywords/{keyword_id}")
def remove_keyword(keyword_id: int, db: Session = Depends(get_db)):
    deleted = CategoryService.remove_keyword(db, keyword_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Keyword not found")
    return {"detail": "Keyword deleted"}
@router.put("/{category_id}", response_model=CategorySchema)
def update_category(
    category_id: int,
    data: CategoryUpdateSchema,
    db: Session = Depends(get_db),
):
    cat = CategoryService.update(db, category_id, data)
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")
    return CategorySchema.model_validate(cat)


@router.delete("/{category_id}")
def delete_category(category_id: int, db: Session = Depends(get_db)):
    try:
        deleted = CategoryService.delete(db, category_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Category not found")
        return {"detail": "Deleted"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

