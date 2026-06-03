from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="icici_savings_v1",
    bank=BankType.ICICI,
    statement_type=StatementType.SAVINGS,
    required_text=("icici bank",),
    preferred_order=("table", "single_line", "multiline"),
)