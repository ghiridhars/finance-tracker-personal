"""
Unit tests for LLM parser functions.

Tests JSON-to-schema conversion, date parsing, and error handling
without making actual LLM API calls.
"""
import pytest
from datetime import date
from decimal import Decimal

from app.models.enums import TransactionType
from app.parsers.llm_parser import (
    _json_to_statement,
    _json_to_savings_statement,
    _parse_date,
)


# ── _parse_date ────────────────────────────────────────────────

class TestLlmParseDate:
    def test_iso_format(self):
        assert _parse_date("2024-01-15") == date(2024, 1, 15)

    def test_dd_mm_yyyy_dash(self):
        assert _parse_date("15-01-2024") == date(2024, 1, 15)

    def test_dd_mm_yyyy_slash(self):
        assert _parse_date("15/01/2024") == date(2024, 1, 15)

    def test_month_name_format(self):
        assert _parse_date("15 Jan 2024") == date(2024, 1, 15)

    def test_full_month_name(self):
        assert _parse_date("15 January 2024") == date(2024, 1, 15)

    def test_us_format(self):
        assert _parse_date("Jan 15, 2024") == date(2024, 1, 15)

    def test_empty_returns_none(self):
        assert _parse_date("") is None
        assert _parse_date(None) is None

    def test_invalid_returns_none(self):
        assert _parse_date("not-a-date") is None

    def test_whitespace_trimmed(self):
        assert _parse_date("  2024-01-15  ") == date(2024, 1, 15)


# ── _json_to_statement (credit card) ──────────────────────────

class TestJsonToStatement:
    def test_full_statement(self):
        data = {
            "statement_date": "2024-02-28",
            "due_date": "2024-03-15",
            "card_number": "4632 02XX XXXX 4418",
            "card_holder_name": "JOHN DOE",
            "credit_limit": 200000,
            "total_dues": 15000,
            "minimum_amount_due": 750,
            "transactions": [
                {
                    "date": "2024-02-05",
                    "description": "AMAZON PURCHASE",
                    "amount": 1500.00,
                    "type": "DEBIT",
                    "reference_number": "REF123",
                },
                {
                    "date": "2024-02-10",
                    "description": "PAYMENT RECEIVED",
                    "amount": 5000.00,
                    "type": "CREDIT",
                    "reference_number": None,
                },
            ],
        }
        stmt = _json_to_statement(data)
        assert stmt.statement_date == date(2024, 2, 28)
        assert stmt.due_date == date(2024, 3, 15)
        assert stmt.card_number == "4632 02XX XXXX 4418"
        assert stmt.card_holder_name == "JOHN DOE"
        assert stmt.credit_limit == Decimal("200000")
        assert stmt.total_dues == Decimal("15000")
        assert stmt.minimum_amount_due == Decimal("750")
        assert len(stmt.transactions) == 2
        assert stmt.transactions[0].type == TransactionType.DEBIT
        assert stmt.transactions[0].amount == Decimal("1500")
        assert stmt.transactions[1].type == TransactionType.CREDIT

    def test_minimal_statement(self):
        data = {
            "transactions": [
                {"date": "2024-01-01", "description": "TEST", "amount": 100, "type": "DEBIT"},
            ],
        }
        stmt = _json_to_statement(data)
        assert len(stmt.transactions) == 1
        assert stmt.statement_date is None
        assert stmt.card_number is None

    def test_empty_transactions(self):
        data = {"transactions": []}
        stmt = _json_to_statement(data)
        assert len(stmt.transactions) == 0

    def test_missing_transactions_key(self):
        data = {}
        stmt = _json_to_statement(data)
        assert len(stmt.transactions) == 0

    def test_transaction_with_missing_date(self):
        data = {
            "transactions": [
                {"description": "NO DATE", "amount": 100, "type": "DEBIT"},
            ],
        }
        stmt = _json_to_statement(data)
        assert len(stmt.transactions) == 1
        assert stmt.transactions[0].date is None

    def test_transaction_defaults_to_debit(self):
        """When type is missing, should default to DEBIT."""
        data = {
            "transactions": [
                {"date": "2024-01-01", "description": "TEST", "amount": 100},
            ],
        }
        stmt = _json_to_statement(data)
        assert stmt.transactions[0].type == TransactionType.DEBIT

    def test_case_insensitive_type(self):
        data = {
            "transactions": [
                {"date": "2024-01-01", "description": "TEST", "amount": 100, "type": "credit"},
            ],
        }
        stmt = _json_to_statement(data)
        assert stmt.transactions[0].type == TransactionType.CREDIT


# ── _json_to_savings_statement ────────────────────────────────

class TestJsonToSavingsStatement:
    def test_full_savings_statement(self):
        data = {
            "account_number": "50100123456789",
            "account_holder_name": "JANE DOE",
            "ifsc_code": "HDFC0001234",
            "branch_name": "MG Road Branch",
            "from_date": "2024-01-01",
            "to_date": "2024-01-31",
            "opening_balance": 50000,
            "closing_balance": 52000,
            "transactions": [
                {
                    "date": "2024-01-05",
                    "description": "ATM WITHDRAWAL",
                    "reference_number": "UTR123",
                    "withdrawal_amount": 2000,
                    "deposit_amount": None,
                    "closing_balance": 48000,
                    "type": "DEBIT",
                },
                {
                    "date": "2024-01-10",
                    "description": "NEFT SALARY",
                    "reference_number": None,
                    "withdrawal_amount": None,
                    "deposit_amount": 54000,
                    "closing_balance": 102000,
                    "type": "CREDIT",
                },
            ],
        }
        stmt = _json_to_savings_statement(data)
        assert stmt.account_number == "50100123456789"
        assert stmt.account_holder_name == "JANE DOE"
        assert stmt.ifsc_code == "HDFC0001234"
        assert stmt.from_date == date(2024, 1, 1)
        assert stmt.to_date == date(2024, 1, 31)
        assert stmt.opening_balance == Decimal("50000")
        assert stmt.closing_balance == Decimal("52000")
        assert len(stmt.transactions) == 2
        assert stmt.transactions[0].withdrawal_amount == Decimal("2000")
        assert stmt.transactions[1].deposit_amount == Decimal("54000")

    def test_minimal_savings(self):
        data = {
            "transactions": [
                {
                    "date": "2024-01-01",
                    "description": "TEST",
                    "withdrawal_amount": 100,
                    "type": "DEBIT",
                },
            ],
        }
        stmt = _json_to_savings_statement(data)
        assert len(stmt.transactions) == 1
        assert stmt.account_number is None
        assert stmt.opening_balance is None

    def test_empty_data(self):
        stmt = _json_to_savings_statement({})
        assert len(stmt.transactions) == 0
        assert stmt.account_number is None

    def test_decimal_precision(self):
        """Ensure amounts preserve decimal precision."""
        data = {
            "opening_balance": 1234.56,
            "closing_balance": 5678.90,
            "transactions": [
                {
                    "date": "2024-01-01",
                    "description": "TEST",
                    "deposit_amount": 4444.34,
                    "closing_balance": 5678.90,
                    "type": "CREDIT",
                },
            ],
        }
        stmt = _json_to_savings_statement(data)
        assert stmt.opening_balance == Decimal("1234.56")
        assert stmt.transactions[0].deposit_amount == Decimal("4444.34")

    def test_string_amounts_from_llm(self):
        """LLM might return amounts as strings — Decimal(str(...)) handles it."""
        data = {
            "opening_balance": "50000",
            "transactions": [
                {
                    "date": "2024-01-01",
                    "description": "TEST",
                    "withdrawal_amount": "1500",
                    "type": "DEBIT",
                },
            ],
        }
        stmt = _json_to_savings_statement(data)
        assert stmt.opening_balance == Decimal("50000")
        assert stmt.transactions[0].withdrawal_amount == Decimal("1500")
