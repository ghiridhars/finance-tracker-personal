"""
Unit tests for GenericPdfParser internal methods.

Tests key parsing functions without requiring actual PDF files by calling
the parser's internal methods directly on text/token inputs.
"""
import pytest
from datetime import date
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsers.generic_pdf_parser import GenericPdfParser


@pytest.fixture
def parser():
    return GenericPdfParser()


# ── _parse_amount_or_dash ──────────────────────────────────────

class TestParseAmountOrDash:
    def test_dash_returns_none(self, parser):
        assert parser._parse_amount_or_dash("-") is None

    def test_valid_decimal_amount(self, parser):
        assert parser._parse_amount_or_dash("1,234.56") == Decimal("1234.56")

    def test_valid_integer_amount(self, parser):
        assert parser._parse_amount_or_dash("5000") == Decimal("5000")

    def test_whitespace_padded_dash(self, parser):
        assert parser._parse_amount_or_dash("  -  ") is None

    def test_whitespace_padded_amount(self, parser):
        assert parser._parse_amount_or_dash("  42.50  ") == Decimal("42.50")

    def test_empty_string(self, parser):
        assert parser._parse_amount_or_dash("") is None

    def test_indian_format_amount(self, parser):
        assert parser._parse_amount_or_dash("1,12,206.68") == Decimal("112206.68")

    def test_currency_symbol_amount(self, parser):
        assert parser._parse_amount_or_dash("₹500.00") == Decimal("500.00")


# ── _classify_amounts ──────────────────────────────────────────

class TestClassifyAmounts:
    def test_three_tokens_debit(self, parser):
        # [debit, credit(zero/dash), balance]
        debit, credit, balance = parser._classify_amounts(["5000.00", "-", "45000.00"])
        assert debit == Decimal("5000.00")
        assert credit is None
        assert balance == Decimal("45000.00")

    def test_three_tokens_credit(self, parser):
        # [debit(zero/dash), credit, balance]
        debit, credit, balance = parser._classify_amounts(["-", "10000.00", "55000.00"])
        assert debit is None
        assert credit == Decimal("10000.00")
        assert balance == Decimal("55000.00")

    def test_three_tokens_both_zero(self, parser):
        debit, credit, balance = parser._classify_amounts(["0", "0", "50000.00"])
        assert debit is None
        assert credit is None
        assert balance == Decimal("50000.00")

    def test_two_tokens(self, parser):
        # [amount, balance] — defaults to debit
        debit, credit, balance = parser._classify_amounts(["3000.00", "47000.00"])
        assert debit == Decimal("3000.00")
        assert credit is None
        assert balance == Decimal("47000.00")

    def test_one_token(self, parser):
        debit, credit, balance = parser._classify_amounts(["7500.00"])
        assert debit == Decimal("7500.00")
        assert credit is None
        assert balance is None

    def test_empty_tokens(self, parser):
        assert parser._classify_amounts([]) == (None, None, None)

    def test_three_tokens_with_commas(self, parser):
        debit, credit, balance = parser._classify_amounts(["1,500.00", "-", "48,500.00"])
        assert debit == Decimal("1500.00")
        assert credit is None
        assert balance == Decimal("48500.00")


# ── _try_opening_balance ───────────────────────────────────────

class TestTryOpeningBalance:
    def test_standard_opening_balance(self, parser):
        result = parser._try_opening_balance("Opening Balance 50,000.00")
        assert result == Decimal("50000.00")

    def test_opening_balance_with_cr(self, parser):
        result = parser._try_opening_balance("Opening Balance 1,23,456.78 CR")
        assert result == Decimal("123456.78")

    def test_opening_balance_with_dr(self, parser):
        result = parser._try_opening_balance("Opening Balance 500.00 DR")
        assert result == Decimal("500.00")

    def test_no_opening_balance(self, parser):
        result = parser._try_opening_balance("Some random transaction line 500.00")
        assert result is None

    def test_case_insensitive(self, parser):
        result = parser._try_opening_balance("OPENING BALANCE 25000.00")
        assert result == Decimal("25000.00")

    def test_opening_balance_no_amount(self, parser):
        result = parser._try_opening_balance("Opening Balance")
        assert result is None


# ── _parse_txn_line ────────────────────────────────────────────

class TestParseTxnLine:
    def test_savings_three_amounts(self, parser):
        """Savings line with debit, credit(dash), balance"""
        line = "15/01/2024 UPI-PAYMENT 5,000.00 - 45,000.00"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["date"] == date(2024, 1, 15)
        assert result["description"] == "UPI-PAYMENT"
        assert result["debit"] == Decimal("5000.00")
        assert result["balance"] == Decimal("45000.00")
        assert result["type"] == TransactionType.DEBIT

    def test_savings_credit_transaction(self, parser):
        """Savings line with dash for debit, credit amount, balance"""
        line = "20/01/2024 NEFT-SALARY - 50,000.00 95,000.00"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["date"] == date(2024, 1, 20)
        assert result["credit"] == Decimal("50000.00")
        assert result["type"] == TransactionType.CREDIT

    def test_credit_card_single_amount(self, parser):
        """Credit card line with just one amount"""
        line = "05/02/2024 AMAZON PURCHASE 1,234.56"
        result = parser._parse_txn_line(line, StatementType.CREDIT_CARD)
        assert result is not None
        assert result["date"] == date(2024, 2, 5)
        assert "AMAZON PURCHASE" in result["description"]
        assert result["debit"] == Decimal("1234.56")

    def test_with_serial_number(self, parser):
        """Line starting with serial number before date"""
        line = "001 15/01/2024 ATM WITHDRAWAL 2,000.00 - 43,000.00"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["date"] == date(2024, 1, 15)

    def test_with_value_date(self, parser):
        """Line with two dates (txn date + value date)"""
        line = "15/01/2024 16/01/2024 NEFT TRANSFER 10,000.00 - 35,000.00"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["date"] == date(2024, 1, 15)
        assert result["debit"] == Decimal("10000.00")

    def test_cr_dr_suffix_stripped(self, parser):
        """Trailing CR/DR indicators should be stripped"""
        line = "15/01/2024 NEFT TRANSFER 10,000.00 - 35,000.00 CR"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["balance"] == Decimal("35000.00")

    def test_no_date_returns_none(self, parser):
        """Non-transaction lines should return None"""
        assert parser._parse_txn_line("Page 1 of 5", StatementType.SAVINGS) is None
        assert parser._parse_txn_line("Account Statement", StatementType.SAVINGS) is None
        assert parser._parse_txn_line("", StatementType.SAVINGS) is None

    def test_date_only_no_amounts_returns_none(self, parser):
        """A line with just a date and text but no amounts"""
        result = parser._parse_txn_line("15/01/2024 Some description text only", StatementType.SAVINGS)
        assert result is None

    def test_two_digit_year(self, parser):
        """Dates with 2-digit year"""
        line = "15/01/24 PURCHASE 500.00 49,500.00"
        result = parser._parse_txn_line(line, StatementType.CREDIT_CARD)
        assert result is not None
        assert result["date"].year == 2024

    def test_dash_separated_date(self, parser):
        """Dates with dash separators"""
        line = "15-01-2024 TRANSFER 1,000.00 - 49,000.00"
        result = parser._parse_txn_line(line, StatementType.SAVINGS)
        assert result is not None
        assert result["date"] == date(2024, 1, 15)


# ── _parse_table_rows ────────────────────────────────────────

class TestParseTableRows:
    @pytest.mark.parametrize(
        "description",
        ["SAVINGS ACCOUNT", "PPF ACCOUNT", "TERM DEPOSIT ACCOUNT"],
    )
    def test_skips_account_summary_rows(self, parser, description):
        rows = [
            ["01/05/2026", description, "", "1", "", "5000"],
            [
                "15/10/2018",
                "UPI/828719363445/19:15:21/UPI/211701011000262@vij",
                "",
                "30",
                "",
                "4970",
            ],
        ]
        col_map = {
            "date": 0,
            "description": 1,
            "reference": 2,
            "debit": 3,
            "credit": 4,
            "amount": None,
            "balance": 5,
        }

        transactions = parser._parse_table_rows(
            rows,
            col_map,
            StatementType.SAVINGS,
        )

        assert len(transactions) == 1
        assert transactions[0]["date"] == date(2018, 10, 15)
        assert transactions[0]["description"].startswith("UPI/")
        assert transactions[0]["debit"] == Decimal("30")


# ── extract_metadata ──────────────────────────────────────────

class TestExtractMetadata:
    def test_period_extraction(self):
        text = "Statement from 01/01/2024 to 31/01/2024"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["period_from"] == "01/01/2024"
        assert meta["period_to"] == "31/01/2024"

    def test_period_with_keyword(self):
        text = "Period: 01-01-2024 to 31-01-2024"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["period_from"] == "01-01-2024"
        assert meta["period_to"] == "31-01-2024"

    def test_account_number(self):
        text = "Account Number: 1234567890123"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["account_number"] == "1234567890123"

    def test_account_number_alternate(self):
        text = "A/C No. 9876 5432 1098"
        meta = GenericPdfParser.extract_metadata(text)
        assert "account_number" in meta

    def test_account_number_ignores_word_only_placeholder(self):
        text = "Account Number: NOMINEE"
        meta = GenericPdfParser.extract_metadata(text)
        assert "account_number" not in meta

    def test_account_number_extracts_digits_before_trailing_words(self):
        text = "A/C No. 0557201810135605460437 NOMINEE REGISTERED"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["account_number"] == "0557201810135605460437"

    def test_account_number_ignores_joint_placeholder(self):
        text = "Account No: Joint"
        meta = GenericPdfParser.extract_metadata(text)
        assert "account_number" not in meta

    def test_card_number_masked(self):
        text = "Card Number: 4632 02XX XXXX 4418"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["card_number"] == "4632 02XX XXXX 4418"

    def test_card_number_contiguous(self):
        text = "463202XXXXXX4418"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta["card_number"] == "463202XXXXXX4418"

    def test_no_metadata(self):
        text = "Some random text without any recognizable patterns"
        meta = GenericPdfParser.extract_metadata(text)
        assert meta == {}

    def test_mixed_metadata(self):
        text = (
            "Account Number: 50100123456789\n"
            "Statement from 01/04/2024 to 30/04/2024\n"
        )
        meta = GenericPdfParser.extract_metadata(text)
        assert "account_number" in meta
        assert "period_from" in meta
        assert "period_to" in meta


# ── _build_savings_result / _build_credit_card_result ─────────

class TestBuildResults:
    def test_build_savings_with_opening_balance(self, parser):
        txns = [
            {
                "date": date(2024, 1, 15),
                "description": "ATM",
                "reference": None,
                "debit": Decimal("2000"),
                "credit": None,
                "balance": Decimal("48000"),
                "type": TransactionType.DEBIT,
            },
            {
                "date": date(2024, 1, 20),
                "description": "SALARY",
                "reference": None,
                "debit": None,
                "credit": Decimal("50000"),
                "balance": Decimal("98000"),
                "type": TransactionType.CREDIT,
            },
        ]
        result = parser._build_savings_result(txns, opening_balance=Decimal("50000"))
        assert result.success
        stmt = result.result
        assert stmt.opening_balance == Decimal("50000")
        assert len(stmt.transactions) == 2
        assert stmt.from_date == date(2024, 1, 15)
        assert stmt.to_date == date(2024, 1, 20)

    def test_build_savings_infers_opening_balance(self, parser):
        """When no opening_balance provided, infer from first txn"""
        txns = [
            {
                "date": date(2024, 1, 15),
                "description": "DEBIT",
                "reference": None,
                "debit": Decimal("2000"),
                "credit": None,
                "balance": Decimal("48000"),
                "type": TransactionType.DEBIT,
            },
        ]
        result = parser._build_savings_result(txns)
        assert result.success
        # opening = first_balance + debit = 48000 + 2000 = 50000
        assert result.result.opening_balance == Decimal("50000")

    def test_build_credit_card(self, parser):
        txns = [
            {
                "date": date(2024, 2, 5),
                "description": "AMAZON",
                "reference": "REF123",
                "debit": Decimal("1500"),
                "credit": None,
                "balance": None,
                "type": TransactionType.DEBIT,
            },
            {
                "date": date(2024, 2, 10),
                "description": "PAYMENT",
                "reference": None,
                "debit": None,
                "credit": Decimal("5000"),
                "balance": None,
                "type": TransactionType.CREDIT,
            },
        ]
        result = parser._build_credit_card_result(txns)
        assert result.success
        stmt = result.result
        assert len(stmt.transactions) == 2
        assert stmt.statement_date == date(2024, 2, 10)

    def test_build_empty_transactions(self, parser):
        result = parser._build_result([], StatementType.SAVINGS)
        assert not result.success
        assert "No transactions" in result.error_message
