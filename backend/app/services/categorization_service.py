"""
Auto-categorization engine and merchant normalization.

Responsibilities:
  1. Extract UPI IDs from descriptions and match against known UPI mappings.
  2. Extract merchant name from UPI handles and match against keywords.
  3. Match MCC (Merchant Category Codes) from UPI descriptions → assign category.
  4. Match transaction descriptions against regex patterns for common types.
  5. Match transaction descriptions against category keywords → assign category_id.
  6. Extract a clean merchant name from raw bank descriptions.
  7. Auto-detect own-account transfers from UPI handle patterns.
  8. Learn from user corrections — auto-create UPI handle → category mappings.

Priority order:
  UPI ID match → UPI merchant extraction → MCC code → regex patterns → keyword match.
"""
import logging
import re
import threading
from typing import Optional

from sqlalchemy.orm import Session

from app.models.category import Category, CategoryKeyword, MccCategory
from app.models.upi import UpiId

logger = logging.getLogger(__name__)

# ── UPI ID extraction ────────────────────────────────────────

# Matches UPI handles like user@hdfcbank, swiggy@axisbank, 9876543210@paytm
_UPI_HANDLE_RE = re.compile(r"[\w.-]+@[a-zA-Z][\w]*", re.IGNORECASE)

# Heal PDF extraction artifacts: a short alpha fragment split by a spurious space
# e.g., "@yescr ed/" → the "ed" after the space belongs to the handle
_UPI_HEAL_RE = re.compile(r"\s([a-zA-Z]{1,6})(?=[\s/\-]|$)")


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
    if not match:
        return None
    handle = match.group(0)
    # Try to heal a broken handle: if a short alpha fragment follows the
    # match separated by a single space and ends at a delimiter, join it.
    rest = description[match.end():]
    heal = _UPI_HEAL_RE.match(rest)
    if heal:
        handle += heal.group(1)
    return handle.lower()


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


# Simple helper to avoid repeated string-based category queries per transaction
def _get_category_id_by_name(db: Session, name: str) -> Optional[int]:
    cat = db.query(Category).filter(Category.name == name).first()
    return cat.id if cat else None


# ── MCC (Merchant Category Code) mapping ─────────────────────

# Extract 4-digit MCC from the end of UPI transaction descriptions
# Format: .../5814 or /5812 at the very end of the description
_MCC_RE = re.compile(r"/(\d{4})\s*$")


_MCC_CACHE: dict[str, int] | None = None
_MCC_LOCK = threading.Lock()

def clear_mcc_cache() -> None:
    """Clear the in-memory MCC cache, e.g., if codes are updated via API."""
    global _MCC_CACHE
    with _MCC_LOCK:
        _MCC_CACHE = None

def _get_cached_mcc_category_id(db: Session, mcc: str) -> Optional[int]:
    global _MCC_CACHE
    with _MCC_LOCK:
        if _MCC_CACHE is None:
            _MCC_CACHE = {}
            for row in db.query(MccCategory).all():
                _MCC_CACHE[row.mcc_code] = row.category_id
        return _MCC_CACHE.get(mcc)


def _match_mcc_code(
    db: Session,
    description: str,
) -> Optional[int]:
    """
    Extract a 4-digit MCC code from the end of a UPI transaction description
    and map it using the in-memory cache of the MccCategory table.

    Examples:
        "UPIOUT/.../swiggyupi@axb/5814" → Food & Dining
        "UPIOUT/.../Q529620232@ybl/5262" → Shopping
        "UPIOUT/.../boism-8547085267@boi/Mer/4121" → Transport
    """
    match = _MCC_RE.search(description)
    if not match:
        return None

    mcc = match.group(1)
    
    # 1. Fast memory lookup for the MCC code
    cat_id = _get_cached_mcc_category_id(db, mcc)
    if cat_id:
        return cat_id

    # 2. Try airline range (3000-3350 are all airlines) if not found
    mcc_int = int(mcc)
    if 3000 <= mcc_int <= 3350:
        return _get_category_id_by_name(db, "Travel")

    return None

# ── Own-account transfer detection ───────────────────────────

def _is_own_upi_transfer(
    db: Session,
    upi_handle: str | None,
) -> bool:
    """
    Check if a UPI handle likely belongs to the user by matching
    the local part (username) against known own UPI handles.

    E.g., if 'ghiridhars@ybl' is registered as own, then
    'ghiridhars@axl', 'ghiridhars@barodampay' are also recognized.
    """
    if not upi_handle:
        return False

    local_part = upi_handle.split("@")[0].lower()

    # Skip phone numbers — too ambiguous
    if re.match(r"^\d+$", local_part):
        return False

    # Get all own UPI IDs
    own_upis = db.query(UpiId).filter(UpiId.is_own == True).all()
    for own in own_upis:
        own_local = own.upi_handle.split("@")[0].lower()
        if local_part == own_local:
            return True

    return False


def auto_register_own_upi(
    db: Session,
    upi_handle: str,
) -> bool:
    """
    Registers a UPI handle as own. Assumes it has already been verified as own
    by the caller (e.g. via _is_own_upi_transfer).
    Returns True if registered.
    """
    existing = db.query(UpiId).filter(UpiId.upi_handle == upi_handle).first()
    if existing:
        return False  # Already registered

    new_upi = UpiId(
        upi_handle=upi_handle,
        label=f"Auto-detected own UPI",
        is_own=True,
    )
    db.add(new_upi)
    db.commit()
    logger.info(f"Auto-registered own UPI: {upi_handle}")
    return True


# ── Learn from user corrections ──────────────────────────────

def learn_from_categorization(
    db: Session,
    transaction_description: str | None,
    category_id: int,
) -> bool:
    """
    When a user manually categorizes a transaction, extract the UPI handle
    and auto-create a mapping in the upi_ids table for future auto-categorization.

    This is the self-improving loop: every user correction teaches the system
    to categorize future transactions from the same UPI handle automatically.

    Returns True if a new mapping was created.
    """
    upi_handle = extract_upi_id(transaction_description)
    if not upi_handle:
        return False

    # Don't learn from own-account transfers
    if _is_own_upi_transfer(db, upi_handle):
        return False

    # Check if this UPI handle already has a mapping
    existing = db.query(UpiId).filter(UpiId.upi_handle == upi_handle).first()
    if existing:
        if existing.category_id != category_id:
            # Update existing mapping to the new category
            existing.category_id = category_id
            db.commit()
            logger.info(
                f"Updated UPI mapping: {upi_handle} → category_id={category_id}"
            )
            return True
        return False  # Already mapped correctly

    # Create new UPI handle → category mapping
    new_upi = UpiId(
        upi_handle=upi_handle,
        label=f"Learned from user correction",
        is_own=False,
        category_id=category_id,
    )
    db.add(new_upi)
    db.commit()
    logger.info(f"Learned UPI mapping: {upi_handle} → category_id={category_id}")
    return True


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
        "UPI-SWIGGY-PAYMENT-12345678@OK" → "Swiggy Payment"
        "POS 412345XXXXXX6789 AMAZON SELLER" → "Amazon Seller"
        "NEFT CR-ACME CORP-REF123456789" → "Acme Corp"
        "BIL/ONL/000312/Airtel Prepaid" → "Airtel Prepaid"
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
    keywords: list[CategoryKeyword] | None = None,
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

    if keywords is None:
        keywords = db.query(CategoryKeyword).all()
        # Sort by length descending for longest-match-first
        keywords.sort(key=lambda k: len(k.keyword), reverse=True)

    for kw in keywords:
        if kw.keyword in desc_upper:
            return kw.category_id

    return None


def categorize_and_normalize(
    db: Session,
    description: str | None,
    keywords: list | None = None,
) -> tuple[Optional[int], Optional[str], bool]:
    """
    Convenience function: returns (category_id, merchant_name, is_own_transfer).

    Priority order:
      1. UPI ID match (exact match against learned mapped handles or own handles)
      2. MCC code (4-digit merchant category code from transaction description)
      3. Keyword match (substring search of DB keywords in description)

    Pass pre-fetched `keywords` to avoid repeated DB queries during bulk operations.
    """
    is_own_transfer = False
    category_id = None

    # 1. Try UPI-based categorization first (includes learned mappings)
    upi_cat_id, is_own, upi_handle = match_upi_id(db, description)
    if is_own:
        is_own_transfer = True
        
        # Explicitly map known own transfers to "Self Transfer" category
        self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
        if self_transfer_cat:
            category_id = self_transfer_cat.id
    else:
        category_id = upi_cat_id

    # 1b. Check if this UPI handle belongs to the user (even if not registered yet)
    if not is_own_transfer and upi_handle:
        if _is_own_upi_transfer(db, upi_handle):
            is_own_transfer = True
            auto_register_own_upi(db, upi_handle)
            
            # Map auto-registered own transfer to "Self Transfer"
            self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
            if self_transfer_cat:
                category_id = self_transfer_cat.id

    # 2. Try MCC code matching
    if category_id is None and description:
        category_id = _match_mcc_code(db, description)

    # 3. Fall back to keyword matching if still no category (which natively covers old regexes and aliases)
    if category_id is None:
        if keywords is None:
            keywords = db.query(CategoryKeyword).all()
            keywords.sort(key=lambda k: len(k.keyword), reverse=True)
        category_id = auto_categorize(db, description, keywords=keywords)

    merchant_name = normalize_merchant(description)
    return category_id, merchant_name, is_own_transfer
