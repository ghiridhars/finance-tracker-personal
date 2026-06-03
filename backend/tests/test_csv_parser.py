"""
Unit tests for CSV parser functions.

Tests delimiter detection, column mapping, opening balance calculation,
and transaction parsing without needing real CSV files from banks.
"""
import pytest
from datetime import date
from decimal import Decimal

from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.csv_parser import parse_csv, _read_to_dataframe, _find_header_row_in_df
from app.parsing.patterns import (
    parse_date,
    parse_amount,
    map_columns,
    is_table_header,
    detect_encoding,
)


# ── parse_date ─────────────────────────────────────────────────

class TestParseDate:
    def test_dd_mm_yyyy_slash(self):
        assert parse_date("15/01/2024") == date(2024, 1, 15)

    def test_dd_mm_yyyy_dash(self):
        assert parse_date("15-01-2024") == date(2024, 1, 15)

    def test_dd_mm_yy(self):
        assert parse_date("15/01/24") == date(2024, 1, 15)

    def test_empty_returns_none(self):
        assert parse_date("") is None
        assert parse_date("   ") is None

    def test_invalid_returns_none(self):
        assert parse_date("not-a-date") is None

    def test_whitespace_trimmed(self):
        assert parse_date("  15/01/2024  ") == date(2024, 1, 15)


# ── parse_amount ───────────────────────────────────────────────

class TestParseAmount:
    def test_plain_decimal(self):
        assert parse_amount("1234.56") == Decimal("1234.56")

    def test_comma_separated(self):
        assert parse_amount("1,234.56") == Decimal("1234.56")

    def test_indian_comma_format(self):
        assert parse_amount("1,12,206.68") == Decimal("112206.68")

    def test_currency_symbol_rupee(self):
        assert parse_amount("₹500.00") == Decimal("500.00")

    def test_currency_symbol_dollar(self):
        assert parse_amount("$250.00") == Decimal("250.00")

    def test_zero_returns_none(self):
        assert parse_amount("0") is None

    def test_dash_returns_none(self):
        assert parse_amount("-") is None

    def test_empty_returns_none(self):
        assert parse_amount("") is None
        assert parse_amount(None) is None

    def test_huge_amount_returns_none(self):
        assert parse_amount("99999999999.00") is None

    def test_parenthesized_negative(self):
        result = parse_amount("(500.00)")
        assert result == Decimal("-500.00")

    def test_whitespace_only(self):
        assert parse_amount("   ") is None


# ── map_columns ────────────────────────────────────────────────

class TestMapColumns:
    def test_standard_headers(self):
        headers = ["Date", "Description", "Debit", "Credit", "Balance"]
        result = map_columns(headers)
        assert result["date"] == 0
        assert result["description"] == 1
        assert result["debit"] == 2
        assert result["credit"] == 3
        assert result["balance"] == 4

    def test_alternate_headers(self):
        headers = ["Txn Date", "Narration", "Withdrawal", "Deposit", "Closing Balance"]
        result = map_columns(headers)
        assert result["date"] == 0
        assert result["description"] == 1
        assert result["debit"] == 2
        assert result["credit"] == 3
        assert result["balance"] == 4

    def test_partial_headers(self):
        headers = ["Date", "Particulars", "Amount"]
        result = map_columns(headers)
        assert result["date"] == 0
        assert result["description"] == 1
        assert result["amount"] == 2
        assert result["debit"] is None
        assert result["credit"] is None

    def test_case_insensitive(self):
        headers = ["DATE", "DESCRIPTION", "DEBIT", "CREDIT", "BALANCE"]
        result = map_columns(headers)
        assert result["date"] == 0
        assert result["description"] == 1

    def test_reference_column(self):
        headers = ["Date", "Description", "Ref No", "Debit", "Credit", "Balance"]
        result = map_columns(headers)
        assert result["reference"] == 2

    def test_empty_headers(self):
        result = map_columns([])
        assert result["date"] is None
        assert result["description"] is None

    def test_with_value_date(self):
        headers = ["Date", "Value Date", "Description", "Debit", "Credit"]
        result = map_columns(headers, include_value_date=True)
        assert result["date"] == 0
        assert result["value_date"] == 1


# ── is_table_header ───────────────────────────────────────────

class TestIsTableHeader:
    def test_valid_header(self):
        assert is_table_header(["Date", "Description", "Debit", "Credit", "Balance"])

    def test_date_and_amount_only(self):
        assert is_table_header(["Date", "Amount"])

    def test_no_date_returns_false(self):
        assert not is_table_header(["Description", "Amount", "Balance"])

    def test_empty_returns_false(self):
        assert not is_table_header([])
        assert not is_table_header(None)

    def test_none_cells_handled(self):
        assert is_table_header(["Date", None, "Description", "Debit"])


# ── detect_encoding ───────────────────────────────────────────

class TestDetectEncoding:
    def test_utf8(self):
        content = "Date,Description,Amount\n01/01/2024,Test,100.00".encode("utf-8")
        enc = detect_encoding(content)
        assert enc.lower() in ("utf-8", "ascii")

    def test_latin1(self):
        content = "Date,Description,Amount\n01/01/2024,Café,100.00".encode("latin-1")
        enc = detect_encoding(content)
        assert enc is not None


# ── Delimiter detection via _read_to_dataframe ────────────────

class TestDelimiterDetection:
    def test_comma_delimiter(self):
        content = b"Date,Description,Amount\n01/01/2024,Purchase,500.00\n02/01/2024,Payment,1000.00"
        df = _read_to_dataframe(content, "test.csv")
        assert len(df) == 3  # header + 2 data rows
        assert len(df.columns) >= 3

    def test_tab_delimiter(self):
        content = b"Date\tDescription\tAmount\n01/01/2024\tPurchase\t500.00"
        df = _read_to_dataframe(content, "test.tsv")
        assert len(df) == 2

    def test_semicolon_delimiter(self):
        content = b"Date;Description;Amount\n01/01/2024;Purchase;500.00"
        df = _read_to_dataframe(content, "test.csv")
        assert len(df) == 2


# ── Header row detection ──────────────────────────────────────

class TestHeaderDetection:
    def test_header_at_first_row(self):
        content = b"Date,Description,Debit,Credit,Balance\n01/01/2024,Test,500,,49500"
        df = _read_to_dataframe(content, "test.csv")
        idx, headers = _find_header_row_in_df(df)
        assert idx == 0
        assert "Date" in headers[0]

    def test_header_after_metadata(self):
        content = (
            b"Bank Statement\n"
            b"Account: 1234567890\n"
            b"Date,Description,Debit,Credit,Balance\n"
            b"01/01/2024,Test,500,,49500"
        )
        df = _read_to_dataframe(content, "test.csv")
        idx, headers = _find_header_row_in_df(df)
        assert idx is not None
        assert idx >= 1

    def test_no_header_found(self):
        content = b"random data\nmore random\njust numbers 123"
        df = _read_to_dataframe(content, "test.csv")
        idx, headers = _find_header_row_in_df(df)
        assert idx is None


# ── Full CSV parse: savings ───────────────────────────────────

class TestParseCsvSavings:
    def _make_csv(self, rows: list[str]) -> bytes:
        return "\n".join(rows).encode("utf-8")

    def test_basic_savings_parse(self):
        csv = self._make_csv([
            "Date,Description,Debit,Credit,Balance",
            "01/01/2024,ATM WITHDRAWAL,2000,,48000",
            "05/01/2024,SALARY,,50000,98000",
            "10/01/2024,ELECTRICITY BILL,1500,,96500",
        ])
        result = parse_csv(csv, BankType.HDFC, StatementType.SAVINGS, "test.csv")
        assert result.success
        stmt = result.result
        assert len(stmt.transactions) == 3
        assert stmt.from_date == date(2024, 1, 1)
        assert stmt.to_date == date(2024, 1, 10)
        assert stmt.closing_balance == Decimal("96500")

    def test_opening_balance_computed_from_all_txns(self):
        """Opening balance should use ALL transactions, not just the first."""
        csv = self._make_csv([
            "Date,Description,Debit,Credit,Balance",
            "01/01/2024,WITHDRAWAL,5000,,45000",
            "02/01/2024,DEPOSIT,,10000,55000",
            "03/01/2024,WITHDRAWAL,3000,,52000",
        ])
        result = parse_csv(csv, BankType.SBI, StatementType.SAVINGS, "test.csv")
        assert result.success
        stmt = result.result
        # opening = closing - total_deposits + total_withdrawals
        # opening = 52000 - 10000 + (5000+3000) = 50000
        assert stmt.opening_balance == Decimal("50000")

    def test_single_amount_column(self):
        """When only a single Amount column exists, infer type from sign."""
        csv = self._make_csv([
            "Date,Description,Amount,Balance",
            "01/01/2024,PURCHASE,-500,49500",
            "02/01/2024,REFUND,200,49700",
        ])
        result = parse_csv(csv, BankType.OTHER, StatementType.SAVINGS, "test.csv")
        assert result.success
        stmt = result.result
        assert len(stmt.transactions) == 2
        assert stmt.transactions[0].withdrawal_amount == Decimal("500")
        assert stmt.transactions[1].deposit_amount == Decimal("200")

    def test_empty_csv(self):
        csv = b"Date,Description,Amount\n"
        result = parse_csv(csv, BankType.OTHER, StatementType.SAVINGS, "test.csv")
        assert not result.success

    def test_too_few_rows(self):
        csv = b"only one row"
        result = parse_csv(csv, BankType.OTHER, StatementType.SAVINGS, "test.csv")
        assert not result.success


# ── Full CSV parse: credit card ───────────────────────────────

class TestParseCsvCreditCard:
    def _make_csv(self, rows: list[str]) -> bytes:
        return "\n".join(rows).encode("utf-8")

    def test_basic_credit_card_parse(self):
        csv = self._make_csv([
            "Date,Description,Debit,Credit",
            "05/02/2024,AMAZON,1500,",
            "10/02/2024,PAYMENT,,5000",
        ])
        result = parse_csv(csv, BankType.HDFC, StatementType.CREDIT_CARD, "test.csv")
        assert result.success
        stmt = result.result
        assert len(stmt.transactions) == 2
        assert stmt.transactions[0].type == TransactionType.DEBIT
        assert stmt.transactions[0].amount == Decimal("1500")
        assert stmt.transactions[1].type == TransactionType.CREDIT
        assert stmt.transactions[1].amount == Decimal("5000")

    def test_single_amount_column_credit_card(self):
        """Negative amounts → credit in credit card context."""
        csv = self._make_csv([
            "Date,Description,Amount",
            "05/02/2024,PURCHASE,1500",
            "10/02/2024,REFUND,-500",
        ])
        result = parse_csv(csv, BankType.ICICI, StatementType.CREDIT_CARD, "test.csv")
        assert result.success
        stmt = result.result
        assert stmt.transactions[0].type == TransactionType.DEBIT
        assert stmt.transactions[1].type == TransactionType.CREDIT

    def test_no_transactions(self):
        csv = self._make_csv([
            "Date,Description,Amount",
            "not-a-date,Something,abc",
        ])
        result = parse_csv(csv, BankType.OTHER, StatementType.CREDIT_CARD, "test.csv")
        assert not result.success
