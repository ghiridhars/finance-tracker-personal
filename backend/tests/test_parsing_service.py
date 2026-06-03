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


def _make_statement(*, tx_count: int = 1):
    transactions = [
        SavingsAccountTransactionSchema(
            date=date(2021, 7, 12),
            description=f"Txn {index + 1}",
            withdrawal_amount=100 + index,
            type=TransactionType.DEBIT,
        )
        for index in range(tx_count)
    ]
    return SavingsAccountStatementSchema(transactions=transactions)


def _write_dummy_pdf(tmp_path: Path) -> Path:
    pdf_path = tmp_path / "statement.pdf"
    pdf_path.write_bytes(b"%PDF-1.4 dummy")
    return pdf_path


def _make_service():
    return ParserService(settings_obj=settings, parser_cls=GenericPdfParser)


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


class TestParsingService:
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

        result = _run_parse_statement(service, BankType.BOB, StatementType.SAVINGS)

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

    def test_parse_statement_with_trace_uses_raw_text_metadata_for_validation(self, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        statement = _make_statement(tx_count=1)
        statement.from_date = date(2021, 7, 15)
        statement.to_date = date(2021, 7, 15)
        statement.opening_balance = Decimal("200.00")
        statement.closing_balance = Decimal("100.00")

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "Statement from 01/07/2021 to 31/07/2021"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(statement, strategy="table")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="none"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.BOB, StatementType.SAVINGS)

        assert result["success"] is True
        assert result["trusted"] is True
        assert result["validation"]["summary"]["confidence"] == "high"
        date_range_check = next(
            check for check in result["validation"]["checks"] if check["name"] == "date_range"
        )
        assert date_range_check["status"] == "passed"
        assert "metadata period" in (date_range_check["message"] or "")
        assert trace.validation is not None
        assert trace.validation.trusted is True

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

    def test_parse_statement_with_trace_records_llm_success(self, monkeypatch, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)
        generic_statement = _make_statement(tx_count=0)
        llm_statement = _make_statement(tx_count=3)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                return "raw text"

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.ok(generic_statement, strategy="table")

        monkeypatch.setattr(
            "app.parsers.llm_parser.parse_with_llm_generic",
            lambda raw_text, bank, statement_type: ParseResult.ok(llm_statement, strategy="llm"),
        )

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="ollama"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.HDFC, StatementType.SAVINGS)

        assert result["success"] is True
        assert result["parser"] == "llm"
        assert result["validation"]["summary"]["confidence"] == "medium"
        assert trace.attempts[0].parser == "generic"
        assert trace.attempts[0].status == "failed"
        assert trace.attempts[1].parser == "llm"
        assert trace.attempts[1].status == "success"
        assert any(event.stage == "llm_fallback" and event.status == "ok" for event in trace.events)
        assert trace.failure is None

    def test_parse_statement_with_trace_records_skipped_llm_without_raw_text(self, tmp_path):
        pdf_path = _write_dummy_pdf(tmp_path)

        class FakeGenericPdfParser:
            @staticmethod
            def extract_metadata(raw_text):
                return {}

            def extract_raw_text(self, file_path, password=None):
                raise RuntimeError("raw text unavailable")

            def parse(self, file_path, statement_type, password=None):
                return ParseResult.failure("Could not extract transactions from PDF")

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="ollama"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.HDFC, StatementType.CREDIT_CARD)

        assert result["success"] is False
        assert result["llm_status"] == "skipped_no_raw_text"
        assert any(
            event.stage == "extract_raw_text" and event.status == "warning"
            for event in trace.events
        )
        assert any(
            event.stage == "llm_fallback" and event.status == "skipped"
            for event in trace.events
        )
        assert trace.attempts[1].parser == "llm"
        assert trace.attempts[1].status == "skipped"
        assert trace.failure is not None

    def test_parse_statement_with_trace_isolates_llm_exception_to_fallback_stage(self, monkeypatch, tmp_path):
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
            "app.parsers.llm_parser.parse_with_llm_generic",
            lambda raw_text, bank, statement_type: (_ for _ in ()).throw(RuntimeError("model unavailable")),
        )

        service = _build_service(
            FakeGenericPdfParser,
            settings_obj=SimpleNamespace(llm_provider="ollama"),
            save_temp_file_fn=lambda file_content, prefix: str(pdf_path),
        )

        result, trace = _run_parse_statement_with_trace(service, BankType.HDFC, StatementType.SAVINGS)

        assert result["success"] is False
        assert result["llm_status"] == "attempted"
        assert result["llm_error"] == "model unavailable"
        assert result["parser"] == "none"
        assert trace.failure is not None
        assert trace.failure.stage == "llm_fallback"
        assert trace.failure.code == "parser.llm_fallback_failed"


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