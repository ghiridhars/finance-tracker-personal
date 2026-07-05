from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class InvestmentRule(Base):
    __tablename__ = "investment_rules"

    id: Mapped[int] = mapped_column(primary_key=True)
    platform_name: Mapped[str] = mapped_column(String(100), nullable=False)
    asset_class: Mapped[str] = mapped_column(String(100), nullable=False)
    keywords: Mapped[str | None] = mapped_column(String(500), nullable=True)
