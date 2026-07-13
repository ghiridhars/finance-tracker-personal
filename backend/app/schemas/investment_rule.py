from typing import Optional
from pydantic import BaseModel
from app.schemas.asset_class import AssetClassResponse

class InvestmentRuleBase(BaseModel):
    platform_name: str
    asset_class_id: int
    keywords: Optional[str] = None

class InvestmentRuleCreate(InvestmentRuleBase):
    pass

class InvestmentRuleUpdate(BaseModel):
    platform_name: Optional[str] = None
    asset_class_id: Optional[int] = None
    keywords: Optional[str] = None

class InvestmentRuleResponse(InvestmentRuleBase):
    id: int
    asset_class: AssetClassResponse

    class Config:
        from_attributes = True
