from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="icici_credit_card_v1",
    bank=BankType.ICICI,
    statement_type=StatementType.CREDIT_CARD,
    required_text=("icici bank", "credit card"),
    preferred_order=("table", "cc_simple_multiline", "single_line"),
)
