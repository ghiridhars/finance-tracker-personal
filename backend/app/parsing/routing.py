from dataclasses import dataclass

from app.models.enums import BankType, StatementType
from app.parsing.classifiers import TemplateClassification, classify_template
from app.parsing.profiles import StrategyProfile
from app.parsing.profiles.registry import strategy_order_for_profile


@dataclass(frozen=True, slots=True)
class StrategyRoute:
    statement_type: StatementType
    strategy_order: tuple[str, ...]
    profile: StrategyProfile | None = None
    classification: TemplateClassification | None = None

    @property
    def profile_id(self) -> str | None:
        if self.profile is None:
            return None
        return self.profile.id

    @property
    def source(self) -> str:
        return "profile" if self.profile is not None else "default"


def resolve_strategy_route(
    raw_text: str,
    statement_type: StatementType,
    *,
    bank: BankType | None = None,
) -> StrategyRoute:
    classification = classify_template(raw_text, statement_type, bank=bank)
    profile = classification.profile if classification is not None else None
    return StrategyRoute(
        statement_type=statement_type,
        profile=profile,
        classification=classification,
        strategy_order=strategy_order_for_profile(profile, statement_type),
    )