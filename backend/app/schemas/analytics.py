from pydantic import BaseModel

class InvestmentPlatformSchema(BaseModel):
    platform: str
    total_invested: float
    percentage: float

class InvestmentAssetSchema(BaseModel):
    asset_class: str
    color: str
    icon: str
    total_invested: float
    percentage: float

class InvestmentTrendSchema(BaseModel):
    period: str
    amount: float

class InvestmentAnalyticsResponse(BaseModel):
    total_invested: float
    platforms: list[InvestmentPlatformSchema]
    asset_classes: list[InvestmentAssetSchema]
    trends: list[InvestmentTrendSchema]
