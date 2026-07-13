from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.asset_class import AssetClass


class InvestmentRule(Base):
    __tablename__ = "investment_rules"

    id: Mapped[int] = mapped_column(primary_key=True)
    platform_name: Mapped[str] = mapped_column(String(100), nullable=False)
    asset_class_id: Mapped[int] = mapped_column(ForeignKey("asset_classes.id"), nullable=False)
    keywords: Mapped[str | None] = mapped_column(String(500), nullable=True)

    asset_class: Mapped["AssetClass"] = relationship(
        "AssetClass", back_populates="rules"
    )
