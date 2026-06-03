from app.models.enums import StatementType
from app.parsing.profiles.manifests import PROFILES
from app.parsing.profiles.models import StrategyProfile


_DEFAULT_STRATEGY_ORDER: dict[StatementType, tuple[str, ...]] = {
    StatementType.SAVINGS: ("table", "single_line", "multiline"),
    StatementType.CREDIT_CARD: (
        "table",
        "single_line",
        "cc_multiline",
        "cc_simple_multiline",
        "multiline",
    ),
}


_PROFILES: tuple[StrategyProfile, ...] = PROFILES


def get_profiles(statement_type: StatementType | None = None) -> tuple[StrategyProfile, ...]:
    if statement_type is None:
        return _PROFILES
    return tuple(profile for profile in _PROFILES if profile.statement_type == statement_type)


def strategy_order_for_profile(
    profile: StrategyProfile | None,
    statement_type: StatementType,
) -> tuple[str, ...]:
    default_order = _DEFAULT_STRATEGY_ORDER.get(
        statement_type,
        _DEFAULT_STRATEGY_ORDER[StatementType.SAVINGS],
    )

    ordered_names: list[str] = []
    seen: set[str] = set()

    for strategy_name in (*(profile.preferred_order if profile else ()), *default_order):
        if strategy_name in seen:
            continue
        ordered_names.append(strategy_name)
        seen.add(strategy_name)

    return tuple(ordered_names)