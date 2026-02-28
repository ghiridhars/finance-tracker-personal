"""
Tag CRUD endpoints.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.tag import Tag
from app.schemas.tag import TagSchema, TagCreateSchema

router = APIRouter(prefix="/api/v2/tags", tags=["Tags"])


@router.get("", response_model=list[TagSchema])
def list_tags(db: Session = Depends(get_db)):
    tags = db.query(Tag).order_by(Tag.name).all()
    return [TagSchema.model_validate(t) for t in tags]


@router.post("", response_model=TagSchema, status_code=201)
def create_tag(data: TagCreateSchema, db: Session = Depends(get_db)):
    tag = Tag(name=data.name, color=data.color)
    db.add(tag)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Tag '{data.name}' already exists")
    db.refresh(tag)
    return TagSchema.model_validate(tag)


@router.delete("/{tag_id}")
def delete_tag(tag_id: int, db: Session = Depends(get_db)):
    tag = db.query(Tag).filter(Tag.id == tag_id).first()
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")
    db.delete(tag)
    db.commit()
    return {"detail": "Deleted"}
