from dataclasses import dataclass
from typing import Any

from app.parsing.errors import (
    ERROR_GENERIC_PARSE,
    ERROR_LLM_FALLBACK,
    STAGE_GENERIC_PARSE,
    STAGE_LLM_FALLBACK,
)
from app.parsing.fallbacks.review import ReviewFallbackOutcome


@dataclass(frozen=True, slots=True)
class ParseFailureResult:
    stage: str
    code: str
    payload: dict[str, Any]


def build_parse_success_result(
    *,
    statement: Any,
    raw_text: str,
    parser_name: str,
    strategy: str | None,
    validation,
    review_fallback: ReviewFallbackOutcome | None,
) -> dict[str, Any]:
    return {
        "success": True,
        "statement": statement,
        "rawText": raw_text,
        "parser": parser_name,
        "strategy": strategy,
        "validation": validation.to_dict(),
        "trusted": validation.trusted,
        "review_fallback": review_fallback.to_dict() if review_fallback is not None else None,
    }


def build_parse_failure_result(
    *,
    message: str,
    raw_text: str,
    generic_error: str,
    llm_status: str,
    llm_error: str | None,
) -> ParseFailureResult:
    stage = STAGE_LLM_FALLBACK if llm_status == "attempted" else STAGE_GENERIC_PARSE
    code = ERROR_LLM_FALLBACK if llm_status == "attempted" else ERROR_GENERIC_PARSE

    return ParseFailureResult(
        stage=stage,
        code=code,
        payload={
            "success": False,
            "error": message,
            "rawText": raw_text,
            "parser": "none",
            "generic_error": generic_error,
            "llm_status": llm_status,
            "llm_error": llm_error,
        },
    )