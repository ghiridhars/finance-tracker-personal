from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app.models.investment_rule import InvestmentRule
from app.schemas.investment_rule import InvestmentRuleCreate, InvestmentRuleUpdate, InvestmentRuleResponse

router = APIRouter(prefix="/api/v2/investment-rules", tags=["Investment Rules"])

@router.get("", response_model=List[InvestmentRuleResponse])
def get_investment_rules(db: Session = Depends(get_db)):
    return db.query(InvestmentRule).all()

@router.post("", response_model=InvestmentRuleResponse, status_code=201)
def create_investment_rule(rule: InvestmentRuleCreate, db: Session = Depends(get_db)):
    db_rule = InvestmentRule(**rule.model_dump())
    db.add(db_rule)
    db.commit()
    db.refresh(db_rule)
    return db_rule

@router.put("/{rule_id}", response_model=InvestmentRuleResponse)
def update_investment_rule(rule_id: int, rule: InvestmentRuleUpdate, db: Session = Depends(get_db)):
    db_rule = db.query(InvestmentRule).filter(InvestmentRule.id == rule_id).first()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Investment rule not found")
    
    update_data = rule.model_dump(exclude_unset=True)
    for k, v in update_data.items():
        setattr(db_rule, k, v)
    
    db.commit()
    db.refresh(db_rule)
    return db_rule

@router.delete("/{rule_id}", status_code=204)
def delete_investment_rule(rule_id: int, db: Session = Depends(get_db)):
    db_rule = db.query(InvestmentRule).filter(InvestmentRule.id == rule_id).first()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Investment rule not found")
    db.delete(db_rule)
    db.commit()
