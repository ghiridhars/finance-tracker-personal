from typing import Optional
from pydantic import BaseModel

class InvestmentRuleBase(BaseModel):
    platform_name: str
    asset_class: str
    keywords: Optional[str] = None

class InvestmentRuleCreate(InvestmentRuleBase):
    pass

class InvestmentRuleUpdate(BaseModel):
    platform_name: Optional[str] = None
    asset_class: Optional[str] = None
    keywords: Optional[str] = None

class InvestmentRuleResponse(InvestmentRuleBase):
    id: int

    class Config:
        from_attributes = True
