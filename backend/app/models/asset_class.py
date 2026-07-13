from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AssetClass(Base):
    __tablename__ = "asset_classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    color_hex: Mapped[str] = mapped_column(String(7), nullable=False, default="#4CAF50")
    icon_name: Mapped[str] = mapped_column(String(50), nullable=False, default="account_balance_wallet")
    
    rules: Mapped[list["InvestmentRule"]] = relationship(
        "InvestmentRule", back_populates="asset_class", cascade="all, delete-orphan"
    )
