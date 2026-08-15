from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="federal_savings_v1",
    bank=BankType.FEDERAL_BANK,
    statement_type=StatementType.SAVINGS,
    required_text=("federal bank",),
    preferred_order=("table", "single_line", "multiline"),
)
