from app.models.enums import BankType, StatementType
from app.parsing.profiles.models import StrategyProfile


PROFILE = StrategyProfile(
    id="hdfc_credit_card_v1",
    bank=BankType.HDFC,
    statement_type=StatementType.CREDIT_CARD,
    required_text=("hdfc bank", "credit card"),
    preferred_order=("table", "cc_multiline", "cc_simple_multiline", "single_line"),
)
