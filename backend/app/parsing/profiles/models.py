from dataclasses import dataclass

from app.models.enums import BankType, StatementType


@dataclass(frozen=True, slots=True)
class StrategyProfile:
    id: str
    bank: BankType
    statement_type: StatementType
    required_text: tuple[str, ...]
    preferred_order: tuple[str, ...]