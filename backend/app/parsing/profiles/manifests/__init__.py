from app.parsing.profiles.manifests.bob_savings_v1 import PROFILE as BOB_SAVINGS_V1
from app.parsing.profiles.manifests.hdfc_credit_card_v1 import PROFILE as HDFC_CREDIT_CARD_V1
from app.parsing.profiles.manifests.icici_savings_v1 import PROFILE as ICICI_SAVINGS_V1

PROFILES = (
    BOB_SAVINGS_V1,
    HDFC_CREDIT_CARD_V1,
    ICICI_SAVINGS_V1,
)

__all__ = [
    "BOB_SAVINGS_V1",
    "HDFC_CREDIT_CARD_V1",
    "ICICI_SAVINGS_V1",
    "PROFILES",
]