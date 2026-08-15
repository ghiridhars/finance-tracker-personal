"""Unit tests for GenericPdfParser orchestration and strategy behavior."""
from datetime import date
from decimal import Decimal
from types import SimpleNamespace

import pytest
from pdfminer.pdfdocument import PDFPasswordIncorrect

from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseException
from app.parsers.generic_pdf_parser import GenericPdfParser
from app.parsers.base_parser import ParseResult
from app.parsing.classifiers import classify_template
from app.parsing.extraction.artifacts import ExtractedPageTables, ExtractedTextDocument
from app.parsing.generic_pdf import run_strategy
from app.parsing.routing import StrategyRoute, resolve_strategy_route
from app.parsing.profiles import strategy_order_for_profile
from app.parsing.strategies.multiline_strategy import (
    try_cc_multiline_strategy,
    try_cc_simple_multiline_strategy,
    try_multiline_strategy,
)
from app.parsing.strategies.single_line_strategy import try_single_line_strategy
from app.parsing.strategies.table_strategy import try_table_strategy


@pytest.fixture
def parser():
    return GenericPdfParser()


class TestPasswordErrors:
    def test_parse_surfaces_incorrect_pdf_password(self, parser, tmp_path, monkeypatch):
        filepath = tmp_path / "protected.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        def raise_incorrect_password(*args, **kwargs):
            raise PDFPasswordIncorrect()

        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_pdf_tables",
            lambda file_path, password=None: (_ for _ in ()).throw(ParseException("Incorrect PDF password.")),
        )

        with pytest.raises(ParseException, match="Incorrect PDF password."):
            parser.parse(filepath, StatementType.SAVINGS, password="wrong-password")


class TestStrategyDispatch:
    def test_runs_table_strategy(self):
        header_table = [
            ["DATE", "NARRATION", "CHQ.NO.", "WITHDRAWAL (DR)", "DEPOSIT (CR)", "BALANCE"],
            ["10-08-2021", "UPI/123", "", "", "2000.00", "4006.44 Cr"],
        ]
        extracted_pages = [ExtractedPageTables(page_number=1, tables=[header_table])]

        result = run_strategy(
            "table",
            page_tables=extracted_pages,
            text_document=ExtractedTextDocument.from_text("ignored"),
            statement_type=StatementType.SAVINGS,
        )

        assert result is not None
        assert result.success
        assert len(result.result.transactions) == 1


class TestTableStrategy:
    def test_collects_single_row_continuation_tables(self):
        header_table = [
            ["GHIRIDHAR S", None, None, "SAVINGS ACCOUNT - 05570100013649", None, None],
            ["DATE", "NARRATION", "CHQ.NO.", "WITHDRAWAL (DR)", "DEPOSIT (CR)", "BALANCE"],
            ["01-08-2021", "Opening Balance", "", "", "", "1952.44 Cr"],
        ]
        fragmented_txn_tables = [
            [["10-08-2021", "UPI/122206334631/08:32:02/UPI/virenderganes\nh84-1@", "", "", "2000.00", "4006.44 Cr"]],
            [["20-08-2021", "IMPS/P2A/123210563610/VSREENIVAS/-", "", "", "100.00", "2117.44 Cr"]],
        ]
        nominee_table = [
            ["NOMINEE DETAILS", None, None, None, None],
            ["SR.NO.", "ACCOUNT TYPE", "ACCOUNT NUMBER", "NOMINEE NAME(S)", None],
            ["1", "SAVINGS ACCOUNT", "05570100013649", "1)", "V SREENIVAS"],
        ]
        extracted_pages = [
            ExtractedPageTables(page_number=1, tables=[header_table, *fragmented_txn_tables]),
            ExtractedPageTables(page_number=2, tables=[nominee_table]),
        ]

        result = try_table_strategy(extracted_pages, StatementType.SAVINGS)

        assert result is not None
        assert result.success
        assert len(result.result.transactions) == 2
        assert result.result.transactions[0].description.startswith("UPI/")
        assert result.result.transactions[0].deposit_amount == Decimal("2000.00")
        assert result.result.transactions[1].description.startswith("IMPS/")
        assert result.result.transactions[1].deposit_amount == Decimal("100.00")


class TestMultilineStrategy:
    def test_back_calculates_opening_balance_when_missing(self):
        """When no explicit opening balance exists, back-calculate without mutating direction.

        With previous_balance=None the block parser defaults the first amount to debit.
        opening_balance = balance + debit - credit = 2006.44 + 54.00 - 0 = 2060.44.
        This is arithmetically consistent; direction correction requires user review.
        """
        text = """
06-08-2021
05570100013649:Int.Pd:01-05-2021 to
31-07-2021
54.00
2006.44 Cr
10-08-2021
UPI/122206334631/08:32:02/UPI/virenderganes
h84-1@
2000.00
4006.44 Cr
""".strip()

        result = try_multiline_strategy(text, StatementType.SAVINGS)

        assert result is not None
        assert result.success
        # No-mutation back-calc: first txn stays as debit (54.00), so OB = 2006.44 + 54 - 0
        assert result.result.opening_balance == Decimal("2060.44")
        assert len(result.result.transactions) == 2
        # First transaction must NOT be silently flipped to credit
        first_txn = result.result.transactions[0]
        assert first_txn.withdrawal_amount == Decimal("54.00")
        assert first_txn.deposit_amount is None
        assert first_txn.type == TransactionType.DEBIT

    def test_back_calculates_opening_balance_genuine_debit_not_flipped(self):
        """A genuine first debit must remain a debit even when opening_balance is unknown."""
        text = """
01/10/2025
POS AMAZON PURCHASE
500.00
4,500.00
02/10/2025
NEFT SALARY CREDIT
30,000.00
34,500.00
05/10/2025
ATM WITHDRAWAL
2,000.00
32,500.00
""".strip()

        result = try_multiline_strategy(text, StatementType.SAVINGS)

        assert result is not None
        assert result.success
        # OB = 4500 + 500 - 0 = 5000 (first txn is a debit — must not be flipped)
        assert result.result.opening_balance == Decimal("5000.00")
        first_txn = result.result.transactions[0]
        assert first_txn.withdrawal_amount == Decimal("500.00")
        assert first_txn.deposit_amount is None
        assert first_txn.type == TransactionType.DEBIT

    def test_parses_single_amount_balance_blocks(self):
        text = """
01-08-2021
Opening Balance
1952.44 Cr
06-08-2021
05570100013649:Int.Pd:01-05-2021 to
31-07-2021
54.00
2006.44 Cr
10-08-2021
UPI/122206334631/08:32:02/UPI/virenderganes
h84-1@
2000.00
4006.44 Cr
10-08-2021
UPI/122246848419/08:33:33/UPI/groww.razorp
ay@icic
2000.00
2006.44 Cr
31-08-2021
Closing Balance
2006.44 Cr
""".strip()

        result = try_multiline_strategy(text, StatementType.SAVINGS)

        assert result is not None
        assert result.success
        assert len(result.result.transactions) == 3
        assert result.result.opening_balance == Decimal("1952.44")
        assert result.result.transactions[0].deposit_amount == Decimal("54.00")
        assert result.result.transactions[1].deposit_amount == Decimal("2000.00")
        assert result.result.transactions[2].withdrawal_amount == Decimal("2000.00")

    def test_parses_credit_card_multiline_blocks(self):
        text = """
18/01/2026 | 14:34
AMAZON PURCHASE (Ref# REF123)
C 245.00
IN
19/01/2026 | 08:00
PAYMENT RECEIVED
+ C 1,000.00
OK
""".strip()

        result = try_cc_multiline_strategy(text)

        assert result is not None
        assert result.success
        assert len(result.result.transactions) == 2
        assert result.result.transactions[0].amount == Decimal("245.00")
        assert result.result.transactions[0].reference_number == "REF123"
        assert result.result.transactions[1].amount == Decimal("1000.00")
        assert result.result.transactions[1].type == TransactionType.CREDIT

    def test_parses_credit_card_simple_multiline_blocks(self):
        text = """
01/02/2026
COFFEE SHOP (Ref# SIMP1)
948.00
02/02/2026
CASHBACK CREDIT
8,779.00 Cr
03/02/2026
important information
""".strip()

        result = try_cc_simple_multiline_strategy(text)

        assert result is not None
        assert result.success
        assert len(result.result.transactions) == 2
        assert result.result.transactions[0].amount == Decimal("948.00")
        assert result.result.transactions[0].reference_number == "SIMP1"
        assert result.result.transactions[1].amount == Decimal("8779.00")
        assert result.result.transactions[1].type == TransactionType.CREDIT


class TestSingleLineStrategy:
    def test_collects_continuation_lines_and_opening_balance(self):
        text = """
Opening Balance 5,000.00
15/01/2024 UPI PAYMENT 1,000.00 - 4,000.00
Ref 12345 continuation details
20/01/2024 NEFT SALARY - 10,000.00 14,000.00
""".strip()

        result = try_single_line_strategy(text, StatementType.SAVINGS)

        assert result is not None
        assert result.success
        assert result.result.opening_balance == Decimal("5000.00")
        assert len(result.result.transactions) == 2
        assert "continuation details" in result.result.transactions[0].description


class TestStrategyProfiles:
    def test_resolves_initial_phase5_profiles(self):
        bob_classification = classify_template(
            "Statement of transactions in Savings Account\nWITHDRAWAL (DR)",
            StatementType.SAVINGS,
        )
        hdfc_classification = classify_template(
            "HDFC BANK CREDIT CARD STATEMENT",
            StatementType.CREDIT_CARD,
        )
        icici_classification = classify_template(
            "ICICI Bank credit card statement",
            StatementType.CREDIT_CARD,
        )
        hdfc_savings_classification = classify_template(
            "HDFC Bank savings account statement",
            StatementType.SAVINGS,
        )

        assert bob_classification is not None
        assert bob_classification.profile_id == "bob_savings_v1"
        assert strategy_order_for_profile(bob_classification.profile, StatementType.SAVINGS)[:3] == (
            "multiline",
            "table",
            "single_line",
        )

        assert hdfc_classification is not None
        assert hdfc_classification.profile_id == "hdfc_credit_card_v1"
        assert strategy_order_for_profile(hdfc_classification.profile, StatementType.CREDIT_CARD)[:4] == (
            "table",
            "cc_multiline",
            "cc_simple_multiline",
            "single_line",
        )

        assert hdfc_savings_classification is not None
        assert hdfc_savings_classification.profile_id == "hdfc_savings_v1"

        assert icici_classification is not None
        assert icici_classification.profile_id == "icici_credit_card_v1"

    def test_declared_bank_prevents_wrong_profile_match(self):
        route = resolve_strategy_route(
            "HDFC BANK CREDIT CARD STATEMENT",
            StatementType.CREDIT_CARD,
            bank=None,
        )

        assert route.profile_id == "hdfc_credit_card_v1"

        mismatched_route = resolve_strategy_route(
            "HDFC BANK CREDIT CARD STATEMENT",
            StatementType.CREDIT_CARD,
            bank=BankType.BOB,
        )

        assert mismatched_route.profile_id is None
        assert mismatched_route.source == "default"
        assert mismatched_route.strategy_order[:3] == ("table", "single_line", "cc_multiline")

    def test_parser_consumes_external_strategy_route(
        self,
        parser,
        tmp_path,
        monkeypatch,
    ):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_pdf_tables",
            lambda file_path, password=None: [ExtractedPageTables(page_number=1, tables=[])],
        )
        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_text_document",
            lambda file_path, password=None: ExtractedTextDocument.from_text("ignored"),
        )
        monkeypatch.setattr(
            "app.parsing.generic_pdf.resolve_strategy_route",
            lambda raw_text, statement_type, bank=None: StrategyRoute(
                statement_type=statement_type,
                strategy_order=("multiline", "table", "single_line"),
            ),
        )

        call_order: list[str] = []

        def fake_run_strategy(strategy_name: str, **kwargs):
            call_order.append(strategy_name)
            return ParseResult.ok(SimpleNamespace(transactions=[object()]))

        monkeypatch.setattr("app.parsing.generic_pdf.run_strategy", fake_run_strategy)

        result = parser.parse(filepath, StatementType.SAVINGS)

        assert result.success is True
        assert call_order == ["multiline", "table", "single_line"]
        assert result.strategy == "multiline"

    def test_profile_order_changes_parse_tie_break_for_bob_savings(
        self,
        parser,
        tmp_path,
        monkeypatch,
    ):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_pdf_tables",
            lambda file_path, password=None: [ExtractedPageTables(page_number=1, tables=[])],
        )
        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_text_document",
            lambda file_path, password=None: ExtractedTextDocument.from_text(
                "Statement of transactions in Savings Account"
            ),
        )

        call_order: list[str] = []

        def fake_run_strategy(strategy_name: str, **kwargs):
            call_order.append(strategy_name)
            return ParseResult.ok(SimpleNamespace(transactions=[object()]))

        monkeypatch.setattr("app.parsing.generic_pdf.run_strategy", fake_run_strategy)

        result = parser.parse(filepath, StatementType.SAVINGS)

        assert result.success is True
        assert call_order == ["multiline", "table", "single_line"]
        assert result.strategy == "multiline"

    def test_default_strategy_order_remains_when_no_profile_matches(
        self,
        parser,
        tmp_path,
        monkeypatch,
    ):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_pdf_tables",
            lambda file_path, password=None: [ExtractedPageTables(page_number=1, tables=[])],
        )
        monkeypatch.setattr(
            "app.parsing.generic_pdf.extract_text_document",
            lambda file_path, password=None: ExtractedTextDocument.from_text(
                "Unclassified savings statement"
            ),
        )

        call_order: list[str] = []

        def fake_run_strategy(strategy_name: str, **kwargs):
            call_order.append(strategy_name)
            return ParseResult.ok(SimpleNamespace(transactions=[object()]))

        monkeypatch.setattr("app.parsing.generic_pdf.run_strategy", fake_run_strategy)

        result = parser.parse(filepath, StatementType.SAVINGS)

        assert result.success is True
        assert call_order == ["table", "single_line", "multiline"]
        assert result.strategy == "table"


