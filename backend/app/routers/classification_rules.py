from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.classification_rule import (
    ClassificationRuleSchema,
    ClassificationRuleCreateSchema,
    ClassificationRuleUpdateSchema,
    ClassificationRuleDryRunResult
)
from app.services.classification_rule_service import ClassificationRuleService


router = APIRouter(prefix="/api/v2/classification-rules", tags=["Classification Rules"])


@router.get("", response_model=List[ClassificationRuleSchema])
def list_rules(
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    db: Session = Depends(get_db)
):
    return ClassificationRuleService.list_rules(db, is_active=is_active)


@router.post("", response_model=ClassificationRuleSchema, status_code=status.HTTP_201_CREATED)
def create_rule(
    rule_data: ClassificationRuleCreateSchema,
    db: Session = Depends(get_db)
):
    return ClassificationRuleService.create_rule(db, **rule_data.model_dump())


@router.get("/{rule_id}", response_model=ClassificationRuleSchema)
def get_rule(
    rule_id: int,
    db: Session = Depends(get_db)
):
    rule = ClassificationRuleService.get_rule(db, rule_id)
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Classification rule not found")
    return rule


@router.put("/{rule_id}", response_model=ClassificationRuleSchema)
def update_rule(
    rule_id: int,
    rule_data: ClassificationRuleUpdateSchema,
    db: Session = Depends(get_db)
):
    rule = ClassificationRuleService.update_rule(db, rule_id, **rule_data.model_dump(exclude_unset=True))
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Classification rule not found")
    return rule


@router.delete("/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rule(
    rule_id: int,
    db: Session = Depends(get_db)
):
    success = ClassificationRuleService.delete_rule(db, rule_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Classification rule not found")


@router.post("/{rule_id}/dry-run", response_model=ClassificationRuleDryRunResult)
def dry_run_rule(
    rule_id: int,
    db: Session = Depends(get_db)
):
    try:
        return ClassificationRuleService.dry_run(db, rule_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.post("/{rule_id}/apply")
def apply_rule(
    rule_id: int,
    db: Session = Depends(get_db)
):
    try:
        updated_count = ClassificationRuleService.apply_rule(db, rule_id)
        return {"updated_count": updated_count}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
