"""
Parser registry — maps (BankType, StatementType) to parser classes.

Drop in a new parser class and register it here to support a new bank.
The ParserService uses this registry to dispatch uploads to the correct parser.
"""
import logging
from typing import Type

from app.models.enums import BankType, StatementType
from app.parsers.base_parser import BaseStatementParser

logger = logging.getLogger(__name__)

# Registry: (BankType, StatementType) → parser class
_PARSER_REGISTRY: dict[tuple[BankType, StatementType], Type[BaseStatementParser]] = {}

# Cache of instantiated parsers (singletons)
_PARSER_INSTANCES: dict[tuple[BankType, StatementType], BaseStatementParser] = {}


def register_parser(
    bank: BankType,
    statement_type: StatementType,
    parser_class: Type[BaseStatementParser],
) -> None:
    """Register a parser class for a (bank, statement_type) combination."""
    key = (bank, statement_type)
    _PARSER_REGISTRY[key] = parser_class
    logger.info(f"Registered parser: {bank.value}/{statement_type.value} → {parser_class.__name__}")


def get_parser(bank: BankType, statement_type: StatementType) -> BaseStatementParser | None:
    """
    Get a parser instance for the given bank and statement type.
    Returns None if no parser is registered (caller should fall back to LLM/CSV).
    """
    key = (bank, statement_type)

    # Return cached instance if available
    if key in _PARSER_INSTANCES:
        return _PARSER_INSTANCES[key]

    # Instantiate from registry
    parser_class = _PARSER_REGISTRY.get(key)
    if parser_class is None:
        return None

    instance = parser_class()
    _PARSER_INSTANCES[key] = instance
    return instance


def get_registered_banks() -> list[dict]:
    """Return all registered (bank, statement_type) combinations for API discovery."""
    return [
        {
            "bank": bank.value,
            "statement_type": st.value,
            "parser": _PARSER_REGISTRY[(bank, st)].__name__,
        }
        for bank, st in _PARSER_REGISTRY
    ]


def has_parser(bank: BankType, statement_type: StatementType) -> bool:
    """Check if a regex parser is registered for this combination."""
    return (bank, statement_type) in _PARSER_REGISTRY


def _register_builtin_parsers() -> None:
    """Register all built-in parsers. Called once at module load."""
    # Bank-specific parsers can be registered here when needed.
    # The GenericPdfParser handles most banks via its three strategies:
    #   1. Table extraction  2. Single-line text  3. Multi-line text
    pass


# Auto-register built-in parsers on import
_register_builtin_parsers()
