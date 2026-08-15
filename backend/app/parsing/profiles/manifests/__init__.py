from app.parsing.profiles.manifests.bob.savings_v1 import PROFILE as BOB_SAVINGS_V1
from app.parsing.profiles.manifests.federal.savings_v1 import PROFILE as FEDERAL_SAVINGS_V1
from app.parsing.profiles.manifests.hdfc.credit_card_v1 import PROFILE as HDFC_CREDIT_CARD_V1
from app.parsing.profiles.manifests.hdfc.savings_v1 import PROFILE as HDFC_SAVINGS_V1
from app.parsing.profiles.manifests.icici.credit_card_v1 import PROFILE as ICICI_CREDIT_CARD_V1

PROFILES = (
    BOB_SAVINGS_V1,
    FEDERAL_SAVINGS_V1,
    HDFC_CREDIT_CARD_V1,
    HDFC_SAVINGS_V1,
    ICICI_CREDIT_CARD_V1,
)

__all__ = [
    "BOB_SAVINGS_V1",
    "FEDERAL_SAVINGS_V1",
    "HDFC_CREDIT_CARD_V1",
    "HDFC_SAVINGS_V1",
    "ICICI_CREDIT_CARD_V1",
    "PROFILES",
]