from dataclasses import dataclass
from typing import Iterable

from app.models.enums import BankType, StatementType
from app.parsing.profiles import StrategyProfile
from app.parsing.profiles.registry import get_profiles


@dataclass(frozen=True, slots=True)
class TemplateClassification:
    profile: StrategyProfile
    matched_fragments: tuple[str, ...]
    score: int
    bank_constrained: bool

    @property
    def profile_id(self) -> str:
        return self.profile.id


def classify_template(
    raw_text: str,
    statement_type: StatementType,
    *,
    bank: BankType | None = None,
    profiles: Iterable[StrategyProfile] | None = None,
) -> TemplateClassification | None:
    normalized = raw_text.casefold()
    candidates = profiles if profiles is not None else get_profiles(statement_type)

    best_match: TemplateClassification | None = None
    best_score = -1

    for profile in candidates:
        if profile.statement_type != statement_type:
            continue
        if bank is not None and profile.bank != bank:
            continue

        matched_fragments = tuple(
            fragment
            for fragment in profile.required_text
            if fragment.casefold() in normalized
        )
        if len(matched_fragments) != len(profile.required_text):
            continue

        score = len(matched_fragments)
        if score <= best_score:
            continue

        best_match = TemplateClassification(
            profile=profile,
            matched_fragments=matched_fragments,
            score=score,
            bank_constrained=bank is not None,
        )
        best_score = score

    return best_match