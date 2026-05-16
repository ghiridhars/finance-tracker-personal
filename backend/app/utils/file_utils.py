"""
Shared file-type inference utilities.

Used by both Google Drive sync and local directory sync to auto-detect
bank and statement type from filenames and folder structure.
"""
from pathlib import Path

from app.models.enums import BankType, ReviewStatus


# Extensions considered as CSV-like (vs PDF)
CSV_EXTENSIONS = {".csv", ".txt", ".tsv", ".xlsx", ".xls"}
SUPPORTED_EXTENSIONS = {".pdf"} | CSV_EXTENSIONS


def review_status_from_parser(parser_used: str) -> str:
    """Return the ReviewStatus value based on which parser handled the file."""
    if "llm" in parser_used.lower():
        return ReviewStatus.LLM_PARSED.value
    return ReviewStatus.AUTO_PARSED.value


def infer_file_type(filename: str, relative_path: str = "") -> tuple[str, str]:
    """
    Infer bank and statement type from filename and path conventions.

    Expected naming patterns (case-insensitive):
      - {BANK}_credit_card*.pdf  → (BANK, CREDIT_CARD)
      - {BANK}_savings*.pdf      → (BANK, SAVINGS)
      - {BANK}_cc*.pdf           → (BANK, CREDIT_CARD)
      - {BANK}*.csv              → (BANK, SAVINGS) [default for CSV]

    Also checks parent folder names for bank hints:
      - /statements/HDFC/jan2025.pdf → (HDFC, ...)

    Falls back to (OTHER, SAVINGS) if pattern doesn't match.

    Args:
        filename: The file's basename (e.g., "hdfc_cc_jan.pdf")
        relative_path: Optional path relative to scan root
                       (e.g., "HDFC/2025/jan.pdf")

    Returns:
        Tuple of (bank_value, statement_type_value) as strings.
    """
    name = filename.lower().replace(" ", "_")
    stem = Path(name).stem

    # Try to extract bank from the beginning of the filename
    detected_bank = "OTHER"
    for bank in BankType:
        if stem.startswith(bank.value.lower()):
            detected_bank = bank.value
            break

    # If filename didn't match, check parent folder names
    if detected_bank == "OTHER" and relative_path:
        path_lower = relative_path.lower().replace(" ", "_")
        for bank in BankType:
            if bank == BankType.OTHER:
                continue
            if bank.value.lower() in path_lower:
                detected_bank = bank.value
                break

    # Detect statement type from filename keywords
    if any(kw in stem for kw in ("credit_card", "creditcard", "_cc_", "_cc.")):
        detected_type = "CREDIT_CARD"
    elif any(kw in stem for kw in ("savings", "saving", "current")):
        detected_type = "SAVINGS"
    else:
        # Check parent path for type hints too
        type_from_path = _detect_type_from_path(relative_path) if relative_path else None
        if type_from_path:
            detected_type = type_from_path
        else:
            # Default: credit card for PDF, savings for CSV
            detected_type = "CREDIT_CARD" if name.endswith(".pdf") else "SAVINGS"

    return detected_bank, detected_type


def _detect_type_from_path(relative_path: str) -> str | None:
    """Check folder names for statement type hints."""
    path_lower = relative_path.lower()
    if any(kw in path_lower for kw in ("credit_card", "creditcard", "cc")):
        return "CREDIT_CARD"
    if any(kw in path_lower for kw in ("savings", "saving", "current")):
        return "SAVINGS"
    return None


def is_supported_file(filename: str) -> bool:
    """Check if a file has a supported statement extension."""
    return Path(filename).suffix.lower() in SUPPORTED_EXTENSIONS


def is_csv_file(filename: str) -> bool:
    """Check if a file is a CSV-like format (vs PDF)."""
    return Path(filename).suffix.lower() in CSV_EXTENSIONS
