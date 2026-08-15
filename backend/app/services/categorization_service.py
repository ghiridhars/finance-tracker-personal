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
from dataclasses import dataclass
from typing import Optional

from sqlalchemy.orm import Session

from app.models.category import Category, MccCategory, CategoryKeyword
from app.models.upi import UpiId
from app.models.enums import ClassificationSource

logger = logging.getLogger(__name__)

@dataclass
class ClassificationResult:
    category_id: int | None = None
    source: str | None = None  # ClassificationSource value
    confidence: float = 0.0  # 0.0 to 1.0
    merchant_name: str | None = None
    # Resolved counterpart bank account when an own-UPI transfer is detected.
    # Populated only if UpiId.account_identifier can be matched to a BankAccount.
    target_bank_account_id: int | None = None


# ── UPI ID extraction ────────────────────────────────────────

# Matches UPI handles like user@hdfcbank, swiggy@axisbank, 9876543210@paytm, s-ghiridhars@ybl
_UPI_HANDLE_RE = re.compile(r"[\w._-]+@[a-zA-Z0-9.-]+", re.IGNORECASE)

# Heal PDF extraction artifacts: a short alpha fragment split by a spurious space
# e.g., "@yescr ed/" → the "ed" after the space belongs to the handle
_UPI_HEAL_RE = re.compile(r"\s([a-zA-Z]{1,6})(?=[\s/\-]|$)")

# Common truncated provider domain stems from PDF margin clips mapped to canonical handles
KNOWN_PROVIDER_ALIASES = {
    "okhdf": "okhdfcbank",
    "okhdfcban": "okhdfcbank",
    "okic": "okicici",
    "axisb": "axisbank",
    "yescred": "yesbank",
    "superyes": "yesbank",
    "ptyb": "paytm",
    "barb": "barodampay",
}


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

    # Heal spurious spaces injected by PDF parsing in standard bank formats.
    # We target slash-bounded or hyphen-bounded chunks that contain an '@'
    # (e.g. ".../gokuldeepma njeri@okaxis/...") to avoid merging regular words.
    if '@' in description:
        match = re.search(r'(?:^|[/:])([^/:]*@[^/:]*)(?:[/:]|$)', description)
        if match:
            raw_chunk = match.group(1)
            if raw_chunk.count(' ') <= 3:
                description = description.replace(raw_chunk, raw_chunk.replace(' ', ''))

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

    # 1. Exact match
    upi_entry = (
        db.query(UpiId)
        .filter(UpiId.upi_handle == upi_handle)
        .first()
    )
    if upi_entry:
        return upi_entry.category_id, upi_entry.is_own, upi_handle

    # 2. Canonical provider alias or prefix fallback
    if "@" in upi_handle:
        username, domain = upi_handle.split("@", 1)
        canonical_domain = KNOWN_PROVIDER_ALIASES.get(domain)
        if canonical_domain:
            canonical_handle = f"{username}@{canonical_domain}"
            upi_entry = (
                db.query(UpiId)
                .filter(UpiId.upi_handle == canonical_handle)
                .first()
            )
            if upi_entry:
                return upi_entry.category_id, upi_entry.is_own, canonical_handle

        # Try prefix matching for margin-clipped domain stems (e.g. user@okhdf matching user@okhdfcbank)
        prefix_pattern = f"{username}@{domain}%"
        upi_entry = (
            db.query(UpiId)
            .filter(UpiId.upi_handle.like(prefix_pattern))
            .first()
        )
        if upi_entry:
            return upi_entry.category_id, upi_entry.is_own, upi_entry.upi_handle

    return None, False, upi_handle


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


def _resolve_bank_account_from_upi(
    db: Session,
    upi_handle: str | None,
) -> int | None:
    """
    Resolve the BankAccount.id that corresponds to a known own UPI handle.

    Matches UpiId.account_identifier against BankAccount.account_number using
    suffix matching to handle masked (XXXX1234) vs full (00011234) number formats.

    Returns BankAccount.id if a unique match is found, else None.
    """
    if not upi_handle:
        return None

    from app.models.bank_account import BankAccount

    local_part = upi_handle.split("@")[0].lower()

    # Find all own UPI entries whose local part matches (same logic as _is_own_upi_transfer)
    own_upis = db.query(UpiId).filter(UpiId.is_own == True).all()
    matched_identifier: str | None = None
    for own in own_upis:
        own_local = own.upi_handle.split("@")[0].lower()
        if local_part == own_local and own.account_identifier:
            matched_identifier = own.account_identifier.strip()
            break

    if not matched_identifier:
        return None

    # Suffix-match: both stored numbers may be masked differently, so compare
    # the trailing 6 digits which are always present
    suffix_len = min(len(matched_identifier), 6)
    suffix = matched_identifier[-suffix_len:]

    all_accounts = db.query(BankAccount).filter(BankAccount.is_active == True).all()
    candidates = [
        a for a in all_accounts
        if a.account_number and a.account_number.endswith(suffix)
    ]

    if len(candidates) == 1:
        return candidates[0].id

    # If multiple accounts share the same suffix (unlikely but possible), try
    # a longer suffix match or exact match as a tiebreaker
    for a in candidates:
        if a.account_number == matched_identifier:
            return a.id

    return None


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

# Minimum and maximum character length for a learnable keyword
_KW_MIN_LEN = 4
_KW_MAX_LEN = 60

# Reusable compiled regexes for keyword extraction
_CITY_LIKE = re.compile(r"^[A-Z]{4,15}$")
_LEADING_NOISE = re.compile(r"^(HTTP|HTTPS)$")



def _extract_learnable_keyword(description: str | None) -> str | None:
    """
    Extract a stable, learnable keyword from a non-UPI transaction description.

    Uses format-specific extraction rules derived from real statement data:

    **PGDR/PRCR format** (old SBI debit-card/netbanking):
        ``PGDR/SWIGGY/25-11-2018 19:10:25/SWT`` → ``SWIGGY``
        ``PRCR/TUTE OF ENGINEERING/ERNAKULAM``   → ``TUTE OF ENGINEERING``

    **NEFT format**:
        ``NEFT-CMS2626671445-NEXTBILLION TECHNOLOGY PRIVATE`` → ``NEXTBILLION TECHNOLOGY``

    **RAZ* format** (Razorpay POS):
        ``RAZ*BUNDL TECHNOLOGIES   BENGALURU`` → ``BUNDL TECHNOLOGIES``
        ``RAZ*LE TRAVENUES TECHNO  Gurgaon``  → ``LE TRAVENUES TECHNO``

    **Credit-card / POS style** (no structural separator):
        ``AMAZON SELLER SERVICES MUMBAI``  → ``AMAZON SELLER SERVICES``
        ``BUNDL TECHNOLOGIES PRIVBANGALORE`` → ``BUNDL TECHNOLOGIES``
        ``WWW SWIGGY IN          GURGAON``  → ``SWIGGY``

    Returns None for descriptions that yield nothing stable (pure reference
    numbers, timestamps, ATM codes, etc.).
    """
    if not description:
        return None

    text = description.strip()
    upper = text.upper()

    # ── 1. PGDR / PRCR format: take segment between 1st and 2nd slash ────
    # PGDR/SWIGGY/25-11-2018…/SWT → SWIGGY
    # PRCR/TUTE OF ENGINEERING/ERNAKULAM → TUTE OF ENGINEERING
    if re.match(r"^P[A-Z]{3}/", upper):
        parts = text.split("/")
        if len(parts) >= 2:
            merchant = parts[1].strip()
            # Skip if the segment is a date or purely numeric
            if merchant and not re.match(r"^[\d/\-: ]+$", merchant):
                return merchant[:_KW_MAX_LEN].upper().strip()
        return None

    # ── Early skip-list: descriptions with no extractable merchant ───────
    # Must run before the NEFT regex to prevent false matches.
    skip_patterns = [
        r"^VCR\s+ARN",
        r"^ATM/",
        r"^\(REF#",
        r"^\d+:INT\.PD:",      # account interest lines like 05570100013649:Int.Pd:
        r"^DCARDFEE/",
        r"^BY CASH$",
        r"^NETBANKING TRANSFER",
        r"^TELE TRANSFER",
        r"^AUTOPAY THANK YOU",
        r"^SMS ALERT CHARGES",
        r"^NEFT CREDIT CARD",   # CC bill payment via NEFT — describes method, not merchant
        r"^NEFT.*\(REF#",       # NEFT with only a ref number — no extractable merchant
    ]
    for pat in skip_patterns:
        if re.match(pat, upper):
            return None

    # ── 2. NEFT format: take text after the numeric reference ────────────
    # NEFT-CMS2626671445-NEXTBILLION TECHNOLOGY PRIVATE → NEXTBILLION TECHNOLOGY PRIVATE
    # Requires a clearly numeric reference segment to avoid matching NEFT CC payment lines.
    neft_match = re.match(
        r"^NEFT[-\s]+([A-Z]{0,4}\d{6,})[-\s]+(.+)$", upper
    )
    if neft_match:
        merchant = neft_match.group(2).strip()
        # Strip trailing location / branch info (short last token often a city)
        parts = merchant.split()
        if len(parts) > 2 and len(parts[-1]) <= 5:
            parts = parts[:-1]
        return " ".join(parts)[:_KW_MAX_LEN].strip() or None

    # ── 3. IMPS format: nothing stable to extract (just ref numbers) ──────
    # IMPS PMT 210505007383 9176 (Ref# ...) → skip
    if re.match(r"^IMPS\b", upper):
        return None

    # ── 4. RAZ* format (Razorpay): take text after RAZ* ──────────────────
    # RAZ*BUNDL TECHNOLOGIES   BENGALURU → BUNDL TECHNOLOGIES
    raz_match = re.match(r"^RAZ\*(.+)$", upper)
    if raz_match:
        merchant = raz_match.group(1).strip()
        # Drop last token if it looks like a city (short, all alpha)
        parts = merchant.split()
        if len(parts) > 1 and re.match(r"^[A-Z]+$", parts[-1]) and len(parts[-1]) <= 10:
            parts = parts[:-1]
        result = " ".join(parts)[:_KW_MAX_LEN].strip()
        return result if len(result) >= _KW_MIN_LEN else None


    # ── 6. Credit-card / POS style: "MERCHANT CITY" ──────────────────────
    # AMAZON SELLER SERVICES MUMBAI → AMAZON SELLER SERVICES
    # BUNDL TECHNOLOGIES PRIVBANGALORE → BUNDL TECHNOLOGIES
    # WWW SWIGGY IN GURGAON → SWIGGY (strip WWW prefix and city suffix)
    words = upper.split()
    if not words:
        return None

    # Strip leading WWW
    if words[0] == "WWW" and len(words) > 1:
        words = words[1:]

    # Drop the last token if it looks like an Indian city name (all-alpha, 4–15 chars)
    # These are typically appended by the bank: BANGALORE, MUMBAI, GURGAON, etc.
    if len(words) > 1 and _CITY_LIKE.match(words[-1]):
        words = words[:-1]

    # Strip leading web-protocol tokens (WWW already handled above, but guard)
    words = [w for w in words if not _LEADING_NOISE.match(w)]

    if not words:
        return None

    # Take up to 4 words as the keyword (merchant names are rarely > 4 words)
    keyword = " ".join(words[:4])[:_KW_MAX_LEN].strip()
    return keyword if len(keyword) >= _KW_MIN_LEN else None



def learn_from_categorization(
    db: Session,
    transaction_description: str | None,
    category_id: int,
) -> tuple[str | None, str | None]:
    """
    When a user manually categorizes a transaction, teach the system so that
    future transactions from the same source are categorized automatically.

    Two-tier learning:

    **Tier 1 — UPI handle learning** (UPI transactions only):
      Extracts the ``@``-handle from the description and persists it in
      ``upi_ids`` with the chosen ``category_id``.  Future UPI transactions
      from the same handle skip the review queue entirely.

    Args:
        db: Active SQLAlchemy session.
        transaction_description: Raw description string from the statement.
        category_id: The category the user assigned.

    Returns:
        ``(learned_upi_handle, learned_keyword)`` — each is the string that
        was learned, or ``None`` if that tier produced no new mapping.
        Both may be ``None`` if nothing was learned.
    """
    learned_handle: str | None = None

    # ── Tier 1: UPI handle learning ──────────────────────────
    upi_handle = extract_upi_id(transaction_description)
    if upi_handle:
        # Don't learn from own-account transfers
        if _is_own_upi_transfer(db, upi_handle):
            return None, None

        existing = db.query(UpiId).filter(UpiId.upi_handle == upi_handle).first()
        if existing:
            if existing.category_id != category_id:
                existing.category_id = category_id
                db.commit()
                logger.info(
                    "Updated UPI mapping: %s → category_id=%d", upi_handle, category_id
                )
                learned_handle = upi_handle
            # else already correct — no-op
        else:
            new_upi = UpiId(
                upi_handle=upi_handle,
                label="Learned from user correction",
                is_own=False,
                category_id=category_id,
            )
            db.add(new_upi)
            db.commit()
            logger.info(
                "Learned UPI mapping: %s → category_id=%d", upi_handle, category_id
            )
            learned_handle = upi_handle

        return learned_handle, None

    # ── Tier 2: Keyword learning ─────────────────────────────
    # If it wasn't a UPI transaction (or if UPI didn't learn anything),
    # try to extract a keyword from the description.
    learned_keyword = _extract_learnable_keyword(transaction_description)
    if learned_keyword:
        existing_kw = (
            db.query(CategoryKeyword)
            .filter(CategoryKeyword.keyword == learned_keyword)
            .first()
        )
        if existing_kw:
            if existing_kw.category_id != category_id:
                existing_kw.category_id = category_id
                db.commit()
                logger.info(
                    "Updated Keyword mapping: %s → category_id=%d", learned_keyword, category_id
                )
            # else already correct — no-op
        else:
            new_kw = CategoryKeyword(
                keyword=learned_keyword,
                category_id=category_id,
                is_learned=True,
            )
            db.add(new_kw)
            db.commit()
            logger.info(
                "Learned Keyword mapping: %s → category_id=%d", learned_keyword, category_id
            )

        return learned_handle, learned_keyword

    return learned_handle, None

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
    amount: float | str | None = None,
    bank_name: str | None = None,
    tx_type: str | None = None,
) -> tuple[ClassificationResult, bool]:
    """
    Unified Single-Pass Classification Engine.

    Priority order:
      1. User-Defined Classification Rules (Highest Priority: 1.0)
      2. UPI ID match (exact match against learned mapped handles or own handles: 0.95)
      3. Own-account UPI transfer detection (0.95)
      4. MCC code (4-digit merchant category code from description: 0.90)
    """
    is_own_transfer = False
    category_id = None
    source = None
    confidence = 0.0

    merchant_name = normalize_merchant(description)

    # 1. Step 1 (Highest Priority): User-Defined Classification Rules
    from app.services.classification_rule_service import ClassificationRuleService

    rule = ClassificationRuleService.match_transaction(
        db,
        description=description or "",
        amount=amount,
        bank=bank_name or "",
        transaction_type=tx_type or "",
        merchant_name=merchant_name or "",
        upi_handle=extract_upi_id(description),
    )

    if rule:
        if rule.mark_as_transfer:
            is_own_transfer = True
            source = ClassificationSource.AUTO_RULE.value
            confidence = 1.0
        elif rule.target_category_id:
            category_id = rule.target_category_id
            source = ClassificationSource.AUTO_RULE.value
            confidence = 1.0
            rule.applied_count = (rule.applied_count or 0) + 1

    # 2. Step 2: Native UPI-based categorization (if user rule didn't match)
    target_bank_account_id: int | None = None
    if category_id is None and not is_own_transfer:
        upi_cat_id, is_own, upi_handle = match_upi_id(db, description)
        if is_own:
            is_own_transfer = True
            target_bank_account_id = _resolve_bank_account_from_upi(db, upi_handle)
            self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
            if self_transfer_cat:
                category_id = self_transfer_cat.id
                source = ClassificationSource.AUTO_UPI.value
                confidence = 0.95
        elif upi_cat_id:
            category_id = upi_cat_id
            source = ClassificationSource.AUTO_UPI.value
            confidence = 0.95

        # Step 3: Check if this UPI handle belongs to the user (even if not registered yet)
        if not is_own_transfer and upi_handle:
            if _is_own_upi_transfer(db, upi_handle):
                is_own_transfer = True
                auto_register_own_upi(db, upi_handle)
                target_bank_account_id = _resolve_bank_account_from_upi(db, upi_handle)
                self_transfer_cat = db.query(Category).filter(Category.name == "Self Transfer").first()
                if self_transfer_cat:
                    category_id = self_transfer_cat.id
                    source = ClassificationSource.AUTO_UPI.value
                    confidence = 0.95

    # 3. Step 4: Native MCC code matching
    if category_id is None and not is_own_transfer and description:
        mcc_cat_id = _match_mcc_code(db, description)
        if mcc_cat_id:
            category_id = mcc_cat_id
            source = ClassificationSource.AUTO_MCC.value
            confidence = 0.90

    # 4. Step 5: Native Keyword matching
    if category_id is None and not is_own_transfer and description:
        desc_upper = description.upper()
        # Fetch all keywords and sort them by length descending so longer keywords match first
        all_keywords = db.query(CategoryKeyword).all()
        all_keywords.sort(key=lambda k: len(k.keyword), reverse=True)
        
        for kw_obj in all_keywords:
            kw = kw_obj.keyword
            if kw in desc_upper:
                category_id = kw_obj.category_id
                source = ClassificationSource.AUTO_KEYWORD.value
                
                # Check for exact word boundary match
                pattern = r'\b' + re.escape(kw) + r'\b'
                if re.search(pattern, desc_upper):
                    confidence = 0.90
                else:
                    confidence = 0.70
                break

    result = ClassificationResult(
        category_id=category_id,
        source=source,
        confidence=confidence,
        merchant_name=merchant_name,
        target_bank_account_id=target_bank_account_id,
    )
    return result, is_own_transfer
