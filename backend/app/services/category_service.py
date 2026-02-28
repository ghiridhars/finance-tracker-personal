"""
Category service — CRUD + default seeding.
"""
import logging
from typing import Optional

from sqlalchemy.orm import Session

from app.models.category import Category, CategoryKeyword
from app.schemas.category import CategorySchema, CategoryCreateSchema, CategoryUpdateSchema

logger = logging.getLogger(__name__)

# ── Default categories with keywords ─────────────────────────
DEFAULT_CATEGORIES: list[dict] = [
    {
        "name": "Food & Dining",
        "icon": "restaurant",
        "color": "#FF5722",
        "keywords": [
            "SWIGGY", "ZOMATO", "UBER EATS", "DOMINOS", "PIZZA HUT",
            "MCDONALDS", "KFC", "STARBUCKS", "CAFE", "RESTAURANT",
            "FOOD", "DINING", "EATERY", "BIRYANI", "BURGER KING",
        ],
    },
    {
        "name": "Transport",
        "icon": "directions_car",
        "color": "#2196F3",
        "keywords": [
            "UBER", "OLA", "RAPIDO", "METRO", "PETROL", "FUEL",
            "PARKING", "TOLL", "DIESEL", "CAB", "AUTO",
        ],
    },
    {
        "name": "Shopping",
        "icon": "shopping_bag",
        "color": "#9C27B0",
        "keywords": [
            "AMAZON", "FLIPKART", "MYNTRA", "AJIO", "MEESHO",
            "NYKAA", "DECATHLON", "SHOPPING", "MALL", "CROMA",
            "RELIANCE DIGITAL",
        ],
    },
    {
        "name": "Bills & Utilities",
        "icon": "receipt_long",
        "color": "#607D8B",
        "keywords": [
            "ELECTRICITY", "WATER", "GAS", "AIRTEL", "JIO",
            "VODAFONE", "BSNL", "BROADBAND", "INTERNET", "TATA POWER",
            "BILL PAYMENT", "RECHARGE", "POSTPAID", "PREPAID",
        ],
    },
    {
        "name": "Entertainment",
        "icon": "movie",
        "color": "#E91E63",
        "keywords": [
            "NETFLIX", "HOTSTAR", "PRIME VIDEO", "SPOTIFY", "YOUTUBE",
            "BOOKMYSHOW", "PVR", "INOX", "DISNEY", "APPLE MUSIC",
            "GAME", "PLAYSTATION", "XBOX",
        ],
    },
    {
        "name": "Health & Medical",
        "icon": "local_hospital",
        "color": "#4CAF50",
        "keywords": [
            "HOSPITAL", "PHARMA", "MEDICAL", "APOLLO", "PHARMACY",
            "DOCTOR", "CLINIC", "DIAGNOSTIC", "PATHOLOGY", "MEDPLUS",
            "NETMEDS", "1MG", "PRACTO",
        ],
    },
    {
        "name": "Travel",
        "icon": "flight",
        "color": "#00BCD4",
        "keywords": [
            "IRCTC", "MAKEMYTRIP", "GOIBIBO", "CLEARTRIP", "YATRA",
            "INDIGO", "AIRINDIA", "SPICEJET", "HOTEL", "OYO",
            "AIRBNB", "VISTARA", "RAILWAY",
        ],
    },
    {
        "name": "Education",
        "icon": "school",
        "color": "#3F51B5",
        "keywords": [
            "SCHOOL", "COLLEGE", "UNIVERSITY", "TUITION", "UDEMY",
            "COURSERA", "BYJU", "UNACADEMY", "EXAM", "BOOKS",
        ],
    },
    {
        "name": "Transfers",
        "icon": "swap_horiz",
        "color": "#795548",
        "keywords": [],  # UPI/NEFT/IMPS are too generic — don't auto-match
    },
    {
        "name": "Salary & Income",
        "icon": "account_balance_wallet",
        "color": "#8BC34A",
        "keywords": [
            "SALARY", "SAL CR", "PAYROLL", "STIPEND",
        ],
    },
    {
        "name": "Investment",
        "icon": "trending_up",
        "color": "#FF9800",
        "keywords": [
            "MUTUAL FUND", "MF PURCHASE", "ZERODHA", "GROWW", "KUVERA",
            "SIP", "DEMAT", "STOCK", "SHARE", "DIVIDEND",
        ],
    },
    {
        "name": "ATM / Cash",
        "icon": "atm",
        "color": "#9E9E9E",
        "keywords": [
            "ATM", "CASH WITHDRAWAL", "CASH WDL", "SELF WDL",
        ],
    },
    {
        "name": "EMI / Loan",
        "icon": "account_balance",
        "color": "#F44336",
        "keywords": [
            "EMI", "LOAN", "REPAYMENT", "BAJAJ FINSERV", "HDFC LTD",
        ],
    },
    {
        "name": "Insurance",
        "icon": "security",
        "color": "#009688",
        "keywords": [
            "INSURANCE", "LIC", "HDFC LIFE", "ICICI PRUDENTIAL",
            "PREMIUM", "POLICYBAZAAR", "STAR HEALTH",
        ],
    },
    {
        "name": "Other",
        "icon": "category",
        "color": "#BDBDBD",
        "keywords": [],
    },
]


class CategoryService:
    """CRUD operations and default seeding for categories."""

    @staticmethod
    def seed_defaults(db: Session) -> None:
        """Insert default categories + keywords if the table is empty."""
        count = db.query(Category).count()
        if count > 0:
            logger.info(f"Categories table already has {count} rows — skipping seed.")
            return

        logger.info("Seeding default categories …")
        for cat_def in DEFAULT_CATEGORIES:
            category = Category(
                name=cat_def["name"],
                icon=cat_def["icon"],
                color=cat_def["color"],
                is_system=True,
            )
            for kw in cat_def["keywords"]:
                category.keywords.append(CategoryKeyword(keyword=kw.upper()))
            db.add(category)

        db.commit()
        logger.info(f"Seeded {len(DEFAULT_CATEGORIES)} default categories.")

    @staticmethod
    def get_all(db: Session) -> list[Category]:
        return db.query(Category).filter(Category.parent_id.is_(None)).all()

    @staticmethod
    def get_by_id(db: Session, category_id: int) -> Optional[Category]:
        return db.query(Category).filter(Category.id == category_id).first()

    @staticmethod
    def create(db: Session, data: CategoryCreateSchema) -> Category:
        category = Category(
            name=data.name,
            icon=data.icon,
            color=data.color,
            parent_id=data.parent_id,
            is_system=False,
        )
        for kw in data.keywords:
            category.keywords.append(CategoryKeyword(keyword=kw.upper()))
        db.add(category)
        db.commit()
        db.refresh(category)
        return category

    @staticmethod
    def update(db: Session, category_id: int, data: CategoryUpdateSchema) -> Optional[Category]:
        category = db.query(Category).filter(Category.id == category_id).first()
        if not category:
            return None
        if data.name is not None:
            category.name = data.name
        if data.icon is not None:
            category.icon = data.icon
        if data.color is not None:
            category.color = data.color
        if data.parent_id is not None:
            category.parent_id = data.parent_id
        db.commit()
        db.refresh(category)
        return category

    @staticmethod
    def delete(db: Session, category_id: int) -> bool:
        category = db.query(Category).filter(Category.id == category_id).first()
        if not category:
            return False
        if category.is_system:
            raise ValueError(f"Cannot delete system category '{category.name}'.")
        db.delete(category)
        db.commit()
        return True

    @staticmethod
    def add_keywords(db: Session, category_id: int, keywords: list[str]) -> Optional[Category]:
        category = db.query(Category).filter(Category.id == category_id).first()
        if not category:
            return None
        for kw in keywords:
            existing = (
                db.query(CategoryKeyword)
                .filter(CategoryKeyword.keyword == kw.upper())
                .first()
            )
            if existing:
                # Move keyword to this category
                existing.category_id = category_id
            else:
                category.keywords.append(CategoryKeyword(keyword=kw.upper()))
        db.commit()
        db.refresh(category)
        return category

    @staticmethod
    def remove_keyword(db: Session, keyword_id: int) -> bool:
        kw = db.query(CategoryKeyword).filter(CategoryKeyword.id == keyword_id).first()
        if not kw:
            return False
        db.delete(kw)
        db.commit()
        return True
