from types import SimpleNamespace

from app.models.enums import BankType, StatementType
from app.parsers.base_parser import ParseResult
from app.parsing.fallbacks import run_llm_fallback


class TestLlmFallback:
    def test_skips_when_provider_is_none(self):
        outcome = run_llm_fallback(
            "raw text",
            BankType.BOB,
            StatementType.SAVINGS,
            llm_provider="none",
        )

        assert outcome.status == "skipped_provider_none"
        assert outcome.parse_result is None
        assert outcome.error == "LLM fallback skipped because llm_provider is set to none."

    def test_skips_when_raw_text_missing(self):
        outcome = run_llm_fallback(
            "",
            BankType.BOB,
            StatementType.SAVINGS,
            llm_provider="ollama",
        )

        assert outcome.status == "skipped_no_raw_text"
        assert outcome.parse_result is None
        assert outcome.error == "LLM fallback skipped because raw text extraction failed."

    def test_returns_attempted_result(self):
        outcome = run_llm_fallback(
            "raw text",
            BankType.BOB,
            StatementType.SAVINGS,
            llm_provider="ollama",
            llm_parse=lambda raw_text, bank, statement_type: ParseResult.ok(
                SimpleNamespace(transactions=[object()]),
                strategy="llm",
            ),
        )

        assert outcome.status == "attempted"
        assert outcome.parse_result is not None
        assert outcome.parse_result.success is True
        assert outcome.error == "0 transactions found"
        assert outcome.exception_message is None

    def test_captures_parser_exception(self):
        outcome = run_llm_fallback(
            "raw text",
            BankType.BOB,
            StatementType.SAVINGS,
            llm_provider="ollama",
            llm_parse=lambda raw_text, bank, statement_type: (_ for _ in ()).throw(RuntimeError("model unavailable")),
        )

        assert outcome.status == "attempted"
        assert outcome.parse_result is None
        assert outcome.error == "model unavailable"
        assert outcome.exception_message == "model unavailable"