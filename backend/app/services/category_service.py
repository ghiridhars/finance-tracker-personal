"""
Category service — CRUD + default seeding.
"""
import logging
import csv
import os
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import exc

from app.models.category import Category, MccCategory, CategoryKeyword
from app.schemas.category import CategorySchema, CategoryCreateSchema, CategoryUpdateSchema

logger = logging.getLogger(__name__)

DEFAULT_CATEGORIES: list[dict] = [
    # Income
    {
        "name": "Salary & Wage",
        "icon": "account_balance_wallet",
        "color": "#8BC34A",
        "keywords": [
            "SALARY", "SAL CR", "PAYROLL", "STIPEND",
        ],
    },
    {
        "name": "Refunds & Rewards",
        "icon": "redeem",
        "color": "#FFD54F",
        "keywords": [
            "REFUND", "CASHBACK", "CASH BACK", "REWARD", "INCENTIVE", "PHONEPEINCENTIVE", "CASH-BACK"
        ],
    },
    {
        "name": "Interest & Dividends",
        "icon": "trending_up",
        "color": "#4CAF50",
        "keywords": [
            "TDINT", "SBINT", "NEFT INT", "INTEREST PAID", "INTEREST CR",
            "INTEREST ON", "INT: ", "TD INT", "FD INT", "RD INT", "DIVIDEND",
            "INT.PD:", "INT:", "INTEREST CREDIT"
        ],
    },
    {
        "name": "Other Income",
        "icon": "monetization_on",
        "color": "#CDDC39",
        "keywords": [
            "RECEIVED FROM"
        ],
    },
    # System / Internal
    {
        "name": "Self Transfer",
        "icon": "sync",
        "color": "#9E9E9E",
        "keywords": [], # Matched via is_own=True
    },
    {
        "name": "ATM / Cash",
        "icon": "atm",
        "color": "#607D8B",
        "keywords": [
            "ATM", "CASH WITHDRAWAL", "CASH WDL", "SELF WDL",
        ],
    },
    {
        "name": "Investment",
        "icon": "show_chart",
        "color": "#FF9800",
        "keywords": [
            "MUTUAL FUND", "MF PURCHASE", "ZERODHA", "GROWW", "KUVERA", "GROWW.ICCL",
            "SIP", "DEMAT", "STOCK", "SHARE",
            "REDEMPTION", "MF REDEMPT", "TMF REDEMPTION", "NFT REDEMPTION", "MMTCPAMP",
            "REPAYMENT CREDIT"
        ],
    },
    # Expenses
    {
        "name": "Food & Dining",
        "icon": "restaurant",
        "color": "#FF5722",
        "keywords": [
            "SWIGGY", "SWIGGYUPI", "ZOMATO", "ZOMATOUPI", "EATSURE", "DOMINOS",
            "RESTAURANT", "CAFE", "BAKERY", "FOOD", "KFC", "MCDONALDS"
        ],
    },
    {
        "name": "Groceries",
        "icon": "local_grocery_store",
        "color": "#8D6E63",
        "keywords": [
            "BLINKIT", "ZEPTO", "BIGBASKET", "INSTAMART", "SUPERMARKET",
            "GROCERY", "DMART", "RELIANCE FRESH", "NATURES BASKET", "DUNZO"
        ],
    },
    {
        "name": "Shopping",
        "icon": "shopping_bag",
        "color": "#9C27B0",
        "keywords": [
            "AMAZON", "AMAZONUPI", "FLIPKART", "MYNTRA", "AJIO", "MEESHO",
            "NYKAA", "DECATHLON", "SHOPPING", "MALL", "CROMA",
            "RELIANCE DIGITAL", "OLX", "OLXNEW", "BHARATPE", "\\.BQR",
            "PAYTMQR", "PAYTM MERCHANT", "PHONEPE MERCHANT", "GPAY MERCHANT", "BOISM"
        ],
    },
    {
        "name": "Transport",
        "icon": "directions_car",
        "color": "#2196F3",
        "keywords": [
            "UBER", "OLA", "RAPIDO", "PETROL", "FUEL", "METRO", "FASTAG",
            "PARKING", "TOLL", "DIESEL", "CAB", "AUTO", "NHAI"
        ],
    },
    {
        "name": "Travel",
        "icon": "flight",
        "color": "#00BCD4",
        "keywords": [
            "IRCTC", "MAKEMYTRIP", "GOIBIBO", "IXIGO", "AIRBNB", "FLIGHT",
            "HOTEL", "CLEARTRIP", "YATRA", "INDIGO", "AIRINDIA", "SPICEJET",
            "OYO", "VISTARA", "RAILWAY"
        ],
    },
    {
        "name": "Bills & Utilities",
        "icon": "receipt_long",
        "color": "#3F51B5",
        "keywords": [
            "ELECTRICITY", "WATER", "GAS", "AIRTEL", "JIO", "JIOMOBILITY",
            "VODAFONE", "BSNL", "BROADBAND", "INTERNET", "TATA POWER",
            "BILL PAYMENT", "RECHARGE", "POSTPAID", "PREPAID",
            "CRED.CLUB", "CRED", "DREAMPLUG", "DREAMPURSE", "BILLDESK"
        ],
    },
    {
        "name": "Entertainment",
        "icon": "movie",
        "color": "#E91E63",
        "keywords": [
            "NETFLIX", "HOTSTAR", "PRIME VIDEO", "SPOTIFY", "YOUTUBE",
            "BOOKMYSHOW", "PVR", "INOX", "DISNEY", "APPLE MUSIC",
            "GAME", "PLAYSTATION", "XBOX", "SONY.RZP", "SONYLIV",
            "ZEE5", "JIOCINEMA", "GOOGLE PLAY", "PLAYSTORE"
        ],
    },
    {
        "name": "Health & Medical",
        "icon": "local_hospital",
        "color": "#F44336",
        "keywords": [
            "HOSPITAL", "PHARMA", "MEDICAL", "APOLLO", "PHARMACY",
            "DOCTOR", "CLINIC", "DIAGNOSTIC", "PATHOLOGY", "MEDPLUS",
            "NETMEDS", "1MG", "PRACTO"
        ],
    },
    {
        "name": "Education",
        "icon": "school",
        "color": "#673AB7",
        "keywords": [
            "SCHOOL", "COLLEGE", "UNIVERSITY", "TUITION", "UDEMY",
            "COURSERA", "BYJU", "UNACADEMY", "EXAM", "BOOKS"
        ],
    },
    {
        "name": "EMI / Loan",
        "icon": "account_balance",
        "color": "#795548",
        "keywords": [
            "EMI", "LOAN", "REPAYMENT", "BAJAJ FINSERV", "HDFC LTD"
        ],
    },
    {
        "name": "Insurance",
        "icon": "security",
        "color": "#009688",
        "keywords": [
            "INSURANCE", "LIC", "HDFC LIFE", "ICICI PRUDENTIAL",
            "PREMIUM", "POLICYBAZAAR", "STAR HEALTH"
        ],
    },
    {
        "name": "Bank Charges",
        "icon": "money_off",
        "color": "#FFC107",
        "keywords": [
            "PENALTY", "FEE", "TDS", "SERVICE CHARGE", "BANK CHARGES", "GST"
        ],
    },
    {
        "name": "Sent Money",
        "icon": "arrow_forward",
        "color": "#E0E0E0",
        "keywords": [
            "PAYMENT TO", "TRANSFER TO"
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
        if count == 0:
            logger.info("Seeding default categories …")
            for cat_def in DEFAULT_CATEGORIES:
                category = Category(
                    name=cat_def["name"],
                    icon=cat_def["icon"],
                    color=cat_def["color"],
                    is_system=True,
                )
                for kw in cat_def.get("keywords", []):
                    category.keywords.append(CategoryKeyword(keyword=kw.upper()))
                db.add(category)
            db.commit()
            logger.info(f"Seeded {len(DEFAULT_CATEGORIES)} default categories.")
            return

        # Table already populated — sync any new default keywords into existing categories
        all_existing_kws = {k.keyword for k in db.query(CategoryKeyword).all()}
        added_count = 0
        for cat_def in DEFAULT_CATEGORIES:
            cat = db.query(Category).filter(Category.name == cat_def["name"]).first()
            if cat:
                for kw in cat_def.get("keywords", []):
                    kw_up = kw.upper().strip()
                    if kw_up and kw_up not in all_existing_kws:
                        cat.keywords.append(CategoryKeyword(keyword=kw_up))
                        all_existing_kws.add(kw_up)
                        added_count += 1
        if added_count > 0:
            db.commit()
            logger.info(f"Synced {added_count} new default category keywords into database.")


    @staticmethod
    def seed_mcc_codes(db: Session) -> int:
        """Seed MCC codes from data/mcc_codes.csv if table is empty."""
        count = db.query(MccCategory).count()
        if count > 0:
            logger.info(f"MccCategory table already has {count} rows — skipping seed.")
            return 0

        # __file__ is backend/app/services/category_service.py
        # We need three dirnames to get to backend, then join with "data"
        csv_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            "data",
            "mcc_codes.csv"
        )
        if not os.path.exists(csv_path):
            logger.warning(f"MCC codes CSV not found at {csv_path}")
            return 0

        logger.info("Seeding MCC codes from CSV...")
        added = 0
        
        # Pre-fetch categories for fast lookup
        categories = db.query(Category).all()
        cat_map = {c.name.lower(): c.id for c in categories}
        cat_map["other"] = cat_map.get("other") or categories[0].id if categories else None
        
        if not cat_map.get("other"):
            return 0

        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat_id = cat_map.get(row["category"].lower())
                if cat_id:
                    mcc = MccCategory(
                        mcc_code=row["mcc_code"],
                        description=row["description"],
                        category_id=cat_id
                    )
                    db.add(mcc)
                    added += 1

        if added:
            db.commit()
            logger.info(f"Seeded {added} MCC codes into the database.")
        return added

    @staticmethod
    def upgrade_keywords(db: Session) -> int:
        """One-off utility to insert keywords for existing defaults if missing."""
        count = 0
        categories = db.query(Category).all()
        cat_map = {c.name: c for c in categories}
        for cat_def in DEFAULT_CATEGORIES:
            c = cat_map.get(cat_def["name"])
            if c:
                existing_kws = {k.keyword for k in c.keywords}
                for kw in cat_def.get("keywords", []):
                    upper_kw = kw.upper()
                    if upper_kw not in existing_kws:
                        c.keywords.append(CategoryKeyword(keyword=upper_kw))
                        count += 1
        if count > 0:
            db.commit()
        return count

    @staticmethod
    def add_keywords(db: Session, category_id: int, keywords: list[str]) -> Category:
        category = CategoryService.get_by_id(db, category_id)
        if not category:
            raise ValueError(f"Category {category_id} not found.")
        
        for kw in keywords:
            upper_kw = kw.upper().strip()
            existing = db.query(CategoryKeyword).filter(CategoryKeyword.keyword == upper_kw).first()
            if existing:
                if existing.category_id != category_id:
                    raise ValueError(f"Keyword '{upper_kw}' already assigned to category '{existing.category.name}'")
            else:
                category.keywords.append(CategoryKeyword(keyword=upper_kw))
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
            upper_kw = kw.upper().strip()
            existing = db.query(CategoryKeyword).filter(CategoryKeyword.keyword == upper_kw).first()
            if existing:
                raise ValueError(f"Keyword '{upper_kw}' already assigned to category '{existing.category.name}'")
            category.keywords.append(CategoryKeyword(keyword=upper_kw))

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

