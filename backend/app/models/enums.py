"""
Enums for the finance tracker application.
Replaces: app.personal.model.TransactionType (Java enum)
"""
import enum


class TransactionType(str, enum.Enum):
    CREDIT = "CREDIT"
    DEBIT = "DEBIT"


class BankType(str, enum.Enum):
    """Supported banks. Extensible — add new banks here, then register a parser."""
    HDFC = "HDFC"
    ICICI = "ICICI"
    SBI = "SBI"
    AXIS = "AXIS"
    KOTAK = "KOTAK"
    YES_BANK = "YES_BANK"
    OTHER = "OTHER"

    @classmethod
    def from_string(cls, value: str) -> "BankType":
        """Case-insensitive lookup with fallback to OTHER."""
        normalized = value.strip().upper().replace(" ", "_")
        try:
            return cls(normalized)
        except ValueError:
            return cls.OTHER


class StatementType(str, enum.Enum):
    """Type of bank statement."""
    SAVINGS = "SAVINGS"
    CREDIT_CARD = "CREDIT_CARD"
    CURRENT = "CURRENT"  # Future: current/business accounts
    CSV = "CSV"  # Generic CSV import


class SourceType(str, enum.Enum):
    """Source of a unified transaction — links back to the original table."""
    SAVINGS = "SAVINGS"
    CREDIT_CARD = "CREDIT_CARD"
