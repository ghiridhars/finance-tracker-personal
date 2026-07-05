"""
Category and CategoryKeyword models for transaction categorization.
"""
from typing import List, Optional

from sqlalchemy import String, Integer, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Category(Base):
    """
    Spending/income category (e.g. Food & Dining, Transport, Salary).
    Supports a single level of parent → child hierarchy.
    """
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    icon: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)   # Material icon name
    color: Mapped[Optional[str]] = mapped_column(String(7), nullable=True)   # Hex color e.g. #FF5722
    parent_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("categories.id"), nullable=True
    )
    is_system: Mapped[bool] = mapped_column(Boolean, default=True)  # Prevent deletion of defaults

    # Relationships
    parent: Mapped[Optional["Category"]] = relationship(
        "Category", remote_side="Category.id", back_populates="children"
    )
    children: Mapped[List["Category"]] = relationship(
        "Category", back_populates="parent", cascade="all, delete-orphan"
    )
    keywords: Mapped[List["CategoryKeyword"]] = relationship(
        back_populates="category", cascade="all, delete-orphan", lazy="selectin"
    )

    def __repr__(self) -> str:
        return f"<Category(id={self.id}, name='{self.name}')>"


class CategoryKeyword(Base):
    """
    Keywords for auto-categorization.  Each keyword maps to exactly one category.
    Matching is case-insensitive substring match against transaction descriptions.

    ``is_learned`` distinguishes keywords auto-created by the learning engine
    (from user corrections in the review pane) from system-seeded or
    user-defined keywords.  This allows future management UIs to surface
    and optionally purge learned keywords separately.
    """
    __tablename__ = "category_keywords"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    keyword: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=False)
    # True = auto-created by the learning engine; False = system-seeded or user-defined
    is_learned: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0", nullable=False)

    category: Mapped["Category"] = relationship(back_populates="keywords")

    def __repr__(self) -> str:
        src = "learned" if self.is_learned else "defined"
        return f"<CategoryKeyword(id={self.id}, keyword='{self.keyword}', category_id={self.category_id}, {src})>"


class MccCategory(Base):
    """
    Maps a 4-digit Merchant Category Code (MCC) to a Category.
    """
    __tablename__ = "mcc_categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    mcc_code: Mapped[str] = mapped_column(String(4), unique=True, nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=False)

    category: Mapped["Category"] = relationship()

    def __repr__(self) -> str:
        return f"<MccCategory(mcc='{self.mcc_code}', category_id={self.category_id})>"
