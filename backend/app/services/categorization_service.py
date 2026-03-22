"""
Auto-categorization engine and merchant normalization.

Responsibilities:
  1. Extract UPI IDs from descriptions and match against known UPI mappings.
  2. Match transaction descriptions against category keywords → assign category_id.
  3. Extract a clean merchant name from raw bank descriptions.

Priority order: UPI ID match → keyword match.
"""
import logging
import re
from typing import Optional

from sqlalchemy.orm import Session

from app.models.category import Category, CategoryKeyword
from app.models.upi import UpiId

logger = logging.getLogger(__name__)

# ── UPI ID extraction ────────────────────────────────────────

# Matches UPI handles like user@hdfcbank, swiggy@axisbank, 9876543210@paytm
_UPI_HANDLE_RE = re.compile(r"[\w.-]+@[a-zA-Z][\w]*", re.IGNORECASE)


def extract_upi_id(description: str | None) -> str | None:
    """
    Extract a UPI handle from a raw bank transaction description.

    Examples:
        "UPI-SWIGGY-swiggy@axisbank-123456" → "swiggy@axisbank"
        "UPI/CR/1234/user@hdfcbank/Ref" → "user@hdfcbank"
        "NEFT CR-ACME CORP-REF123456789" → None
    """
    if not description:
        return None
    match = _UPI_HANDLE_RE.search(description)
    return match.group(0).lower() if match else None


def match_upi_id(
    db: Session,
    description: str | None,
) -> tuple[Optional[int], bool, Optional[str]]:
    """
    Check if the description contains a known UPI handle.

    Returns:
        (category_id, is_own_transfer, matched_upi_handle)
        - category_id: category from the UPI mapping, or None
        - is_own_transfer: True if the UPI belongs to the user's own account
        - matched_upi_handle: the UPI handle that matched, or None
    """
    upi_handle = extract_upi_id(description)
    if not upi_handle:
        return None, False, None

    upi_entry = (
        db.query(UpiId)
        .filter(UpiId.upi_handle == upi_handle)
        .first()
    )
    if not upi_entry:
        return None, False, upi_handle

    return upi_entry.category_id, upi_entry.is_own, upi_handle

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
) -> tuple[Optional[int], Optional[str], bool]:
    """
    Convenience function: returns (category_id, merchant_name, is_own_transfer).

    Priority order:
      1. UPI ID match (most specific)
      2. Keyword match (fallback)
    """
    is_own_transfer = False

    # 1. Try UPI-based categorization first
    upi_cat_id, is_own, _ = match_upi_id(db, description)
    if is_own:
        is_own_transfer = True
    category_id = upi_cat_id

    # 2. Fall back to keyword matching if no UPI category
    if category_id is None:
        category_id = auto_categorize(db, description)

    merchant_name = normalize_merchant(description)
    return category_id, merchant_name, is_own_transfer
