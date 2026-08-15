"""
Enums for the finance tracker application.
Replaces: app.personal.model.TransactionType (Java enum)
"""
import enum


class TransactionType(str, enum.Enum):
    CREDIT = "CREDIT"
    DEBIT = "DEBIT"


class BankType(str, enum.Enum):
    """Supported banks. The generic parser handles any bank."""
    HDFC = "HDFC"
    ICICI = "ICICI"
    SBI = "SBI"
    AXIS = "AXIS"
    KOTAK = "KOTAK"
    YES_BANK = "YES_BANK"
    BOB = "BOB"
    FEDERAL_BANK = "FEDERAL_BANK"
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


class TransferType(str, enum.Enum):
    """Type of inter-account transfer."""
    INTERNAL_TRANSFER = "INTERNAL_TRANSFER"
    CC_BILL_PAYMENT = "CC_BILL_PAYMENT"


class ReviewStatus(str, enum.Enum):
    """Parse confidence / review lifecycle for transactions."""
    AUTO_PARSED = "AUTO_PARSED"      # Generic parser succeeded
    LLM_PARSED = "LLM_PARSED"       # LLM fallback was used
    NEEDS_REVIEW = "NEEDS_REVIEW"    # Low confidence or parse issues
    REVIEWED = "REVIEWED"            # Manually verified by user


class ClassificationSource(str, enum.Enum):
    """How a transaction's category was assigned."""
    AUTO_KEYWORD = "AUTO_KEYWORD"
    AUTO_UPI = "AUTO_UPI"
    AUTO_MCC = "AUTO_MCC"
    AUTO_PATTERN = "AUTO_PATTERN"
    AUTO_RULE = "AUTO_RULE"
    USER_REVIEW = "USER_REVIEW"
    USER_DIRECT = "USER_DIRECT"


class AccountSubtype(str, enum.Enum):
    SAVINGS = "SAVINGS"
    SALARY = "SALARY"
    CURRENT = "CURRENT"
    CREDIT_CARD = "CREDIT_CARD"
    LOAN_HOME = "LOAN_HOME"
    LOAN_PERSONAL = "LOAN_PERSONAL"
    LOAN_VEHICLE = "LOAN_VEHICLE"
    LOAN_EDUCATION = "LOAN_EDUCATION"
    LOAN_OTHER = "LOAN_OTHER"
    FD = "FD"
    RD = "RD"
    MF = "MF"
    DEMAT = "DEMAT"
    PPF = "PPF"
    NPS = "NPS"
    OTHER = "OTHER"
