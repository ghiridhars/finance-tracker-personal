from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="bob_savings_v1",
    bank=BankType.BOB,
    statement_type=StatementType.SAVINGS,
    required_text=("statement of transactions in savings account",),
    preferred_order=("multiline", "table", "single_line"),
)