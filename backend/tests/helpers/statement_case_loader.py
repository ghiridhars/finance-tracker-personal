import os
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

from app.parsers.base_parser import ParseException
from app.parsers.generic_pdf_parser import GenericPdfParser
from tests.fixtures.statement_cases import (
    DEFAULT_STATEMENT_CORPUS_CANDIDATES,
    DEFAULT_STATEMENT_CORPUS_ENV_VAR,
    StatementCase,
)


def resolve_statement_corpus_root() -> Path | None:
    env_value = os.getenv(DEFAULT_STATEMENT_CORPUS_ENV_VAR)
    candidates: list[Path] = []
    if env_value:
        candidates.append(Path(env_value).expanduser())
    candidates.extend(DEFAULT_STATEMENT_CORPUS_CANDIDATES)

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return None


def resolve_case_path(case: StatementCase, corpus_root: Path | None = None) -> Path:
    root = corpus_root or resolve_statement_corpus_root()
    if root is None:
        raise FileNotFoundError(
            f"Statement corpus not found. Set {DEFAULT_STATEMENT_CORPUS_ENV_VAR}."
        )

    path = root / case.relative_path
    if not path.exists():
        raise FileNotFoundError(f"Statement case file not found: {path}")

    return path


def get_case_password(case: StatementCase) -> str | None:
    if not case.password_env_var:
        return None

    value = os.getenv(case.password_env_var)
    if value is None:
        return None

    stripped = value.strip()
    return stripped or None


def case_skip_reason(case: StatementCase, corpus_root: Path | None = None) -> str | None:
    root = corpus_root or resolve_statement_corpus_root()
    if root is None:
        return f"Statement corpus not found. Set {DEFAULT_STATEMENT_CORPUS_ENV_VAR}."

    if not (root / case.relative_path).exists():
        return f"Statement case file not found: {root / case.relative_path}"

    if case.requires_password and not get_case_password(case):
        return f"Set {case.password_env_var} to run {case.key}."

    return None


def available_statement_cases(
    cases: list[StatementCase] | tuple[StatementCase, ...],
    corpus_root: Path | None = None,
    *,
    require_passwords: bool = False,
) -> list[StatementCase]:
    root = corpus_root or resolve_statement_corpus_root()
    if root is None:
        return []

    available: list[StatementCase] = []
    for case in cases:
        if not (root / case.relative_path).exists():
            continue
        if require_passwords and case.requires_password and not get_case_password(case):
            continue
        available.append(case)

    return available


def parse_statement_case(case: StatementCase, corpus_root: Path | None = None) -> dict[str, Any]:
    path = resolve_case_path(case, corpus_root)
    password = get_case_password(case)
    parser = GenericPdfParser()

    try:
        result = parser.parse(path, case.statement_type, password=password)
    except ParseException as exc:
        return {
            "case": case.key,
            "bucket": case.bucket,
            "file": str(path),
            "success": False,
            "strategy": None,
            "transaction_count": 0,
            "opening_balance": None,
            "closing_balance": None,
            "from_date": None,
            "to_date": None,
            "error": str(exc),
            "exception_type": exc.__class__.__name__,
        }
    except Exception as exc:  # pragma: no cover - unexpected failures should still snapshot cleanly
        return {
            "case": case.key,
            "bucket": case.bucket,
            "file": str(path),
            "success": False,
            "strategy": None,
            "transaction_count": 0,
            "opening_balance": None,
            "closing_balance": None,
            "from_date": None,
            "to_date": None,
            "error": str(exc),
            "exception_type": exc.__class__.__name__,
        }

    statement = result.result
    transactions = getattr(statement, "transactions", []) if statement else []

    return {
        "case": case.key,
        "bucket": case.bucket,
        "file": str(path),
        "success": result.success,
        "strategy": result.strategy,
        "transaction_count": len(transactions),
        "opening_balance": _serialize_value(getattr(statement, "opening_balance", None)),
        "closing_balance": _serialize_value(getattr(statement, "closing_balance", None)),
        "from_date": _serialize_value(getattr(statement, "from_date", None)),
        "to_date": _serialize_value(getattr(statement, "to_date", None)),
        "error": result.error_message,
        "exception_type": None,
    }


def _serialize_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, date):
        return value.isoformat()
    return value