from typing import Optional
from pydantic import BaseModel

class AssetClassBase(BaseModel):
    name: str
    color_hex: str
    icon_name: str

class AssetClassCreate(AssetClassBase):
    pass

class AssetClassUpdate(BaseModel):
    name: Optional[str] = None
    color_hex: Optional[str] = None
    icon_name: Optional[str] = None

class AssetClassResponse(AssetClassBase):
    id: int

    class Config:
        from_attributes = True
