"""
Auto-categorization engine and merchant normalization.

Responsibilities:
  1. Match transaction descriptions against category keywords → assign category_id.
  2. Extract a clean merchant name from raw bank descriptions.
"""
import logging
import re
from typing import Optional

from sqlalchemy.orm import Session

from app.models.category import Category, CategoryKeyword

logger = logging.getLogger(__name__)

# ── Merchant normalization patterns ──────────────────────────

# Common bank prefixes/suffixes to strip
_BANK_NOISE = re.compile(
    r"(?i)"
    r"\b(UPI|NEFT|IMPS|RTGS|POS|BIL|INB|MOB|CDM|ATM|NFS|VPS|TRF)\b"
    r"|(?:CR|DR)\b"
    r"|\b\d{6,}"           # long numeric references
    r"|\bXX+\d+"           # masked card/account numbers like XX1234
    r"|\b\d{2}[/-]\d{2}[/-]\d{2,4}\b"  # date patterns
    r"|\b[A-Z0-9]{12,}\b"  # long alpha-numeric references
    r"|[/@\\|*#]"          # special chars
)

# Whitespace cleanup
_MULTI_SPACE = re.compile(r"\s{2,}")


def normalize_merchant(description: str | None) -> str | None:
    """
    Extract a clean merchant name from a raw bank transaction description.

    Examples:
        "UPI-SWIGGY-PAYMENT-12345678@OK" → "SWIGGY PAYMENT"
        "POS 412345XXXXXX6789 AMAZON SELLER" → "AMAZON SELLER"
        "NEFT CR-ACME CORP-REF123456789" → "ACME CORP"
        "BIL/ONL/000312/Airtel Prepaid" → "AIRTEL PREPAID"
    """
    if not description:
        return None

    text = description.upper().strip()

    # Replace hyphens with spaces for UPI-style descriptions
    text = text.replace("-", " ").replace("_", " ")

    # Remove noise tokens
    text = _BANK_NOISE.sub(" ", text)

    # Remove trailing/leading whitespace and collapse multi-spaces
    text = _MULTI_SPACE.sub(" ", text).strip()

    # If nothing meaningful remains, return None
    if not text or len(text) < 2:
        return None

    return text.title()  # "SWIGGY PAYMENT" → "Swiggy Payment"


def auto_categorize(
    db: Session,
    description: str | None,
) -> Optional[int]:
    """
    Match a transaction description against category keywords.
    Returns the category_id of the first matching keyword, or None.

    Matching strategy:
      - Case-insensitive substring match.
      - Keywords are checked longest-first to prefer specific matches
        (e.g., "UBER EATS" before "UBER").
    """
    if not description:
        return None

    desc_upper = description.upper()

    # Load all keywords (they're small — O(hundreds) at most)
    keywords = (
        db.query(CategoryKeyword)
        .order_by(CategoryKeyword.keyword.desc())  # longest first (rough heuristic)
        .all()
    )

    # Sort by length descending for longest-match-first
    keywords.sort(key=lambda k: len(k.keyword), reverse=True)

    for kw in keywords:
        if kw.keyword in desc_upper:
            return kw.category_id

    return None


def categorize_and_normalize(
    db: Session,
    description: str | None,
) -> tuple[Optional[int], Optional[str]]:
    """
    Convenience function: returns (category_id, merchant_name) for a description.
    """
    category_id = auto_categorize(db, description)
    merchant_name = normalize_merchant(description)
    return category_id, merchant_name
