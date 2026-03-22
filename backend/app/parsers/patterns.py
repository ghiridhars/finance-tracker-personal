"""
Shared column/header patterns and utility functions for statement parsers.

Centralizes regex patterns, date parsing, and amount parsing used by
both csv_parser.py and generic_pdf_parser.py.
"""
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Optional

from dateutil import parser as dateutil_parser

MAX_REASONABLE_AMOUNT = Decimal("10000000000")  # 10 billion

# ── Column header patterns (case-insensitive) ──────────────────

DATE_PATTERNS = [
    r"^date$", r"txn\s*date", r"transaction\s*date", r"value\s*date",
    r"posting\s*date", r"^dt$",
]

VALUE_DATE_PATTERNS = [r"value\s*date"]

DESCRIPTION_PATTERNS = [
    r"description", r"narration", r"particulars", r"details",
    r"remarks", r"transaction\s*details",
]

DEBIT_PATTERNS = [
    r"^debit$", r"withdrawal", r"^dr$", r"amount\s*\(?\s*debit\s*\)?",
    r"debit\s*amount",
]

CREDIT_PATTERNS = [
    r"^credit$", r"^deposit", r"^cr$", r"amount\s*\(?\s*credit\s*\)?",
    r"credit\s*amount",
]

AMOUNT_PATTERNS = [
    r"^amount$", r"transaction\s*amount", r"txn\s*amount",
]

BALANCE_PATTERNS = [
    r"balance", r"closing\s*balance", r"running\s*balance",
    r"available\s*balance",
]

REFERENCE_PATTERNS = [
    r"reference", r"ref\s*no", r"txn\s*ref", r"chq.*ref",
    r"utr", r"tran\s*id", r"transaction\s*id",
]

# ── Lines to skip (headers, footers, noise) ─────────────────────

NOISE_PATTERN = re.compile(
    r"^("
    r"page\s+\d"
    r"|note[:\s]"
    r"|this\s+is\s+a\s+computer"
    r"|account\s+statement"
    r"|serial\s+(transaction|no)"
    r"|no\s+date\s+date"
    r"|statement\s+(of|from|period)"
    r"|customer\s+id"
    r"|customer\s+name"
    r"|account\s+(details|information|name|number|scheme)"
    r"|branch\s+(name|sol)"
    r"|value\s+tran"
    r"|date\s+(value|particulars)"
    r"|date\s+type\s+details"
    r"|\d+x\d+\s+contact"
    r"|savings\s+account"
    r"|available\s+balance"
    r"|mode\s+of\s+operation"
    r"|joint\s+holders"
    r"|nomination"
    r"|account\s+open"
    r"|micr\s+code"
    r"|ifsc"
    r"|swift\s+code"
    r"|mobile\s+number"
    r"|email"
    r"|kyc\s+status"
    r"|re-kyc"
    r"|address"
    r"|communication"
    r"|ckyc"
    r"|sb\s+fedbook"
    r"|click\s+here"
    r")",
    re.IGNORECASE,
)

# Leading date regex — optional serial number + date
LEADING_DATE_RE = re.compile(
    r"^(?:\d{1,4}\s+)?"  # optional serial number
    r"(\d{2}[/-]\d{2}[/-]\d{2,4})"  # date
)

# Amount with decimals (Indian or Western comma format)
DECIMAL_AMOUNT_RE = re.compile(r"^[\d,]+\.\d{2}$")

# Plain integer amount
INTEGER_AMOUNT_RE = re.compile(r"^\d[\d,]*$")


# ── Date parsing ───────────────────────────────────────────────

def parse_date(value: str) -> Optional[date]:
    """
    Parse a date string using python-dateutil for robust format handling.
    Uses dayfirst=True since Indian bank statements use DD/MM/YYYY.
    """
    if not value or not value.strip():
        return None
    try:
        return dateutil_parser.parse(value.strip(), dayfirst=True).date()
    except (ValueError, OverflowError):
        return None


# ── Amount parsing ─────────────────────────────────────────────

def parse_amount(value: str | None) -> Optional[Decimal]:
    """Parse an amount string, stripping currency symbols and commas."""
    if not value or not value.strip():
        return None
    cleaned = re.sub(r"[₹$€£\s]", "", value.strip())
    cleaned = cleaned.replace("(", "-").replace(")", "")
    if not cleaned or cleaned == "-" or cleaned == "0":
        return None
    cleaned = cleaned.replace(",", "")
    if not re.fullmatch(r"[+-]?\d+(?:\.\d{1,2})?", cleaned):
        return None
    try:
        amount = Decimal(cleaned)
        if abs(amount) > MAX_REASONABLE_AMOUNT:
            return None
        return amount
    except InvalidOperation:
        return None


# ── Column mapping ─────────────────────────────────────────────

def map_columns(headers: list[str], include_value_date: bool = False) -> dict[str, Optional[int]]:
    """
    Map header names to column indices using pattern matching.
    Works for both CSV headers and PDF table headers.
    """
    mapping: dict[str, Optional[int]] = {
        "date": None,
        "description": None,
        "debit": None,
        "credit": None,
        "amount": None,
        "balance": None,
        "reference": None,
    }
    if include_value_date:
        mapping["value_date"] = None

    pattern_map = {
        "date": DATE_PATTERNS,
        "description": DESCRIPTION_PATTERNS,
        "debit": DEBIT_PATTERNS,
        "credit": CREDIT_PATTERNS,
        "amount": AMOUNT_PATTERNS,
        "balance": BALANCE_PATTERNS,
        "reference": REFERENCE_PATTERNS,
    }
    if include_value_date:
        pattern_map["value_date"] = VALUE_DATE_PATTERNS

    for idx, header in enumerate(headers):
        if not header:
            continue
        h = header.replace("\n", " ").strip().lower()
        if not h:
            continue

        for field, patterns in pattern_map.items():
            if mapping[field] is not None:
                continue
            for p in patterns:
                if re.search(p, h):
                    mapping[field] = idx
                    break

    return mapping


def is_table_header(row: list[str | None]) -> bool:
    """Check if a row looks like a table header (has date + desc/amount columns)."""
    if not row:
        return False
    cells = [(c or "").replace("\n", " ").strip().lower() for c in row]
    has_date = any(
        re.search(p, cell) for cell in cells for p in DATE_PATTERNS
    )
    has_desc = any(
        re.search(p, cell) for cell in cells for p in DESCRIPTION_PATTERNS
    )
    has_amount = any(
        re.search(p, cell)
        for cell in cells
        for p in DEBIT_PATTERNS + CREDIT_PATTERNS + AMOUNT_PATTERNS + BALANCE_PATTERNS
    )
    return has_date and (has_desc or has_amount)


def get_cell(row: list[str | None], idx: int | None) -> str:
    """Safely get a cell value by index."""
    if idx is None or idx >= len(row):
        return ""
    return (row[idx] or "").strip()


def detect_encoding(content: bytes) -> str:
    """Detect the encoding of byte content using charset-normalizer."""
    from charset_normalizer import from_bytes

    result = from_bytes(content).best()
    if result:
        return str(result.encoding)
    return "utf-8"
