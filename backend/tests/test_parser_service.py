from datetime import date
from pathlib import Path

from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)
from app.services.parser_service import ParserService


def _make_statement(
    *,
    tx_count: int = 1,
    from_date: date | None = None,
    to_date: date | None = None,
    opening_balance=None,
    closing_balance=None,
):
    transactions = [
        SavingsAccountTransactionSchema(
            date=date(2021, 7, 12),
            description=f"Txn {index + 1}",
            withdrawal_amount=100 + index,
            type=TransactionType.DEBIT,
        )
        for index in range(tx_count)
    ]
    return SavingsAccountStatementSchema(
        transactions=transactions,
        from_date=from_date,
        to_date=to_date,
        opening_balance=opening_balance,
        closing_balance=closing_balance,
    )


def _write_dummy_pdf(tmp_path: Path) -> Path:
    pdf_path = tmp_path / "statement.pdf"
    pdf_path.write_bytes(b"%PDF-1.4 dummy")
    return pdf_path


class TestParserService:
    def test_reports_generic_and_llm_failure_details(self, monkeypatch, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.failure("Could not extract transactions from PDF")

        monkeypatch.setattr(
            "app.services.parser_service.GenericPdfParser",
            FakeGenericPdfParser,
        )
        monkeypatch.setattr(
            "app.services.parser_service.settings.llm_provider",
            "ollama",
        )
        monkeypatch.setattr(
            ParserService,
            "_save_temp_file",
            lambda self, file_content, prefix: str(pdf_path),
        )
        monkeypatch.setattr(
            "app.parsers.llm_parser.parse_with_llm_generic",
            lambda raw_text, bank, statement_type: ParseResult.failure("Ollama returned no transactions"),
        )

        result = _run_parse_statement(
            ParserService(),
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )

        assert result["success"] is False
        assert result["generic_error"] == "Could not extract transactions from PDF"
        assert result["llm_status"] == "attempted"
        assert result["llm_error"] == "Ollama returned no transactions"
        assert "Generic parser failed: Could not extract transactions from PDF" in result["error"]
        assert "LLM fallback failed: Ollama returned no transactions" in result["error"]

    def test_allows_bob_single_transaction_generic_parse(self, monkeypatch, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        incomplete_statement = _make_statement(tx_count=1)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(incomplete_statement, strategy="table")

        monkeypatch.setattr(
            "app.services.parser_service.GenericPdfParser",
            FakeGenericPdfParser,
        )
        monkeypatch.setattr(
            "app.services.parser_service.settings.llm_provider",
            "none",
        )
        monkeypatch.setattr(
            ParserService,
            "_save_temp_file",
            lambda self, file_content, prefix: str(pdf_path),
        )

        result = _run_parse_statement(
            ParserService(),
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )

        assert result["success"] is True
        assert result["parser"] == "generic"
        assert result["strategy"] == "table"

    def test_allows_bob_single_transaction_when_statement_period_present(
        self, monkeypatch, tmp_path
    ):
        pdf_path = _write_dummy_pdf(tmp_path)
        valid_statement = _make_statement(
            tx_count=1,
            from_date=date(2021, 7, 1),
            to_date=date(2021, 7, 31),
        )

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(valid_statement, strategy="table")

        monkeypatch.setattr(
            "app.services.parser_service.GenericPdfParser",
            FakeGenericPdfParser,
        )
        monkeypatch.setattr(
            "app.services.parser_service.settings.llm_provider",
            "none",
        )
        monkeypatch.setattr(
            ParserService,
            "_save_temp_file",
            lambda self, file_content, prefix: str(pdf_path),
        )

        result = _run_parse_statement(
            ParserService(),
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )

        assert result["success"] is True
        assert result["parser"] == "generic"
        assert result["strategy"] == "table"


def _run_parse_statement(service: ParserService, *, bank: BankType, statement_type: StatementType):
    import asyncio

    return asyncio.run(
        service.parse_statement(
            b"%PDF-1.4 dummy",
            "statement.pdf",
            bank,
            statement_type,
        )
    )