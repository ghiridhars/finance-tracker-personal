from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="hdfc_savings_v1",
    bank=BankType.HDFC,
    statement_type=StatementType.SAVINGS,
    required_text=("hdfc bank", "savings"),
    preferred_order=("multiline", "table", "single_line"),
)
