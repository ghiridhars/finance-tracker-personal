from datetime import date
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

from app.config import settings
from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.parsers.generic_pdf_parser import GenericPdfParser
from app.parsing.service import (
    ParserService,
    apply_account_identity,
    format_failure_error,
    save_temp_file as default_save_temp_file,
    validate_pdf,
)
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)


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


def _build_service(parser_cls, *, settings_obj=None, save_temp_file_fn=None):
    settings_obj = settings_obj or SimpleNamespace(llm_provider="none")
    return ParserService(
        parser_cls=parser_cls,
        settings_obj=settings_obj,
        validate_pdf_fn=lambda file_content: validate_pdf(
            file_content,
            settings_obj=settings_obj,
        ),
        save_temp_file_fn=save_temp_file_fn or default_save_temp_file,
        apply_account_identity_fn=apply_account_identity,
        format_failure_error_fn=format_failure_error,
    )


class TestParserService:
    def test_applies_account_identity_from_shared_metadata(self):
        statement = SavingsAccountStatementSchema(transactions=[])

        apply_account_identity(
            statement,
            BankType.BOB,
            StatementType.SAVINGS,
            "Account Number: 1234567890123",
        )

        assert statement.account_holder_name == "Bob"
        assert statement.account_number == "1234567890123"

    def test_applies_card_identity_from_shared_metadata(self):
        statement = type("CardStatement", (), {"card_holder_name": None, "card_number": None})()

        apply_account_identity(
            statement,
            BankType.HDFC,
            StatementType.CREDIT_CARD,
            "Card Number: 4632 02XX XXXX 4418",
        )

        assert statement.card_holder_name == "Hdfc"
        assert statement.card_number == "4632 02XX XXXX 4418"

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
            "app.parsing.service.parser_service.GenericPdfParser",
            FakeGenericPdfParser,
        )
        monkeypatch.setattr(
            "app.parsing.service.parser_service.settings.llm_provider",
            "ollama",
        )
        monkeypatch.setattr(
            "app.parsing.service.parser_service.save_temp_file",
            lambda file_content, prefix: str(pdf_path),
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
            "app.parsing.service.parser_service.GenericPdfParser",
            FakeGenericPdfParser,
        )
        monkeypatch.setattr(
            "app.parsing.service.parser_service.settings.llm_provider",
            "none",
        )
        monkeypatch.setattr(
            "app.parsing.service.parser_service.save_temp_file",
            lambda file_content, prefix: str(pdf_path),
        )

        result = _run_parse_statement(
            ParserService(),
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )

        assert result["success"] is True
        assert result["parser"] == "generic"
        assert result["strategy"] == "table"

    def test_parse_statement_includes_serialized_trace(self, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        statement = _make_statement(tx_count=2)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(statement, strategy="table")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result = _run_parse_statement(
            service, bank=BankType.BOB, statement_type=StatementType.SAVINGS
        )

        assert result["success"] is True
        assert result["trace"]["context"]["filename"] == "statement.pdf"
        assert result["trace"]["events"][-1]["stage"] == "cleanup_temp_file"

    def test_parse_statement_with_trace_records_success(self, monkeypatch, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        statement = _make_statement(tx_count=2)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(statement, strategy="table")

        monkeypatch.setattr("app.parsing.service.parser_service.GenericPdfParser", FakeGenericPdfParser)
        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.BOB, StatementType.SAVINGS)

        assert result["success"] is True
        assert result["trusted"] is True
        assert result["validation"]["trusted"] is True
        assert result["validation"]["summary"]["status"] == "trusted"
        assert result["validation"]["summary"]["confidence"] == "medium"
        assert result["parser"] == "generic"
        assert trace.events[0].stage == "validate_pdf"
        assert trace.attempts[0].parser == "generic"
        assert trace.attempts[0].status == "success"
        assert trace.events[-1].stage == "cleanup_temp_file"
        assert trace.failure is None
        assert trace.validation is not None
        assert trace.validation.trusted is True

    def test_parse_statement_with_trace_passes_declared_bank_to_bank_aware_parser(self, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        statement = _make_statement(tx_count=1)
        captured: dict[str, object] = {}

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "Statement of transactions in Savings Account"

            def parse(self, file_path, statement_type, password=None, bank=None):
                captured["bank"] = bank
                return ParseResult.ok(statement, strategy="multiline")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.BOB, StatementType.SAVINGS)

        assert result["success"] is True
        assert captured["bank"] == BankType.BOB
        assert trace.attempts[0].strategy == "multiline"

    def test_parse_statement_with_trace_records_validation_warning(self, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        statement = _make_statement(tx_count=1)
        statement.from_date = date(2021, 7, 1)
        statement.to_date = date(2021, 7, 31)
        statement.opening_balance = Decimal("100.00")
        statement.closing_balance = Decimal("999.00")

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(statement, strategy="table")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.BOB, StatementType.SAVINGS)

        assert result["success"] is True
        assert result["trusted"] is False
        assert result["validation"]["trusted"] is False
        assert result["validation"]["summary"]["status"] == "review_required"
        assert result["validation"]["summary"]["confidence"] == "low"
        assert result["review_fallback"] is not None
        assert result["review_fallback"]["action"] == "manual_review"
        assert result["review_fallback"]["reason_codes"] == ["validate.balance.reconciliation_failed"]
        assert any(
            check["code"] == "validate.balance.reconciliation_failed"
            for check in result["validation"]["checks"]
        )
        assert trace.validation is not None
        assert trace.validation.trusted is False
        assert any(event.stage == "validate_statement" and event.status == "warning" for event in trace.events)
        assert any(event.stage == "review_fallback" and event.status == "warning" for event in trace.events)

    def test_parse_statement_with_trace_records_failure_details(self, monkeypatch, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.failure("Could not extract transactions from PDF")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.BOB, StatementType.SAVINGS)

        assert result["success"] is False
        assert result["generic_error"] == "Could not extract transactions from PDF"
        assert trace.attempts[0].status == "failed"
        assert trace.attempts[1].status == "skipped"
        assert trace.attempts[1].parser == "llm"
        assert trace.events[-1].stage == "cleanup_temp_file"
        assert trace.failure is not None
        assert trace.failure.stage == "generic_parse"
        assert trace.failure.code == "parser.generic_parse_failed"


def _run_parse_statement_with_trace(service: ParserService, bank: BankType, statement_type: StatementType):
    import asyncio

    return asyncio.run(
        service.parse_statement_with_trace(
            file_content=b"%PDF-1.4 dummy",
            filename="statement.pdf",
            bank=bank,
            statement_type=statement_type,
        )
    )


def _run_parse_statement(service: ParserService, bank: BankType, statement_type: StatementType):
    import asyncio

    return asyncio.run(
        service.parse_statement(
            file_content=b"%PDF-1.4 dummy",
            filename="statement.pdf",
            bank=bank,
            statement_type=statement_type,
        )
    )