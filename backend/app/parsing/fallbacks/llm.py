from dataclasses import dataclass
from typing import Callable, Literal

from app.models.enums import BankType, StatementType
from app.parsers.base_parser import ParseResult

LlmFallbackStatus = Literal["attempted", "skipped_provider_none", "skipped_no_raw_text"]


@dataclass(frozen=True, slots=True)
class LlmFallbackOutcome:
    status: LlmFallbackStatus
    parse_result: ParseResult | None = None
    error: str | None = None
    exception_message: str | None = None


def run_llm_fallback(
    raw_text: str,
    bank: BankType,
    statement_type: StatementType,
    *,
    llm_provider: str,
    llm_parse: Callable[[str, BankType, StatementType], ParseResult] | None = None,
) -> LlmFallbackOutcome:
    if llm_provider.lower() == "none":
        return LlmFallbackOutcome(
            status="skipped_provider_none",
            error="LLM fallback skipped because llm_provider is set to none.",
        )

    if not raw_text:
        return LlmFallbackOutcome(
            status="skipped_no_raw_text",
            error="LLM fallback skipped because raw text extraction failed.",
        )

    parser = llm_parse
    if parser is None:
        from app.parsers.llm_parser import parse_with_llm_generic

        parser = parse_with_llm_generic

    try:
        parse_result = parser(raw_text, bank, statement_type)
        return LlmFallbackOutcome(
            status="attempted",
            parse_result=parse_result,
            error=parse_result.error_message or "0 transactions found",
        )
    except Exception as exc:
        message = str(exc) or exc.__class__.__name__
        return LlmFallbackOutcome(
            status="attempted",
            error=message,
            exception_message=message,
        )