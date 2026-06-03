from datetime import date
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsing.line_parsing import classify_amounts, parse_txn_line, try_opening_balance


class TestLineParsing:
    def test_try_opening_balance_extracts_amount(self):
        assert try_opening_balance("Opening Balance 1,23,456.78 CR") == Decimal("123456.78")

    def test_try_opening_balance_returns_none_for_non_balance_text(self):
        assert try_opening_balance("Some random transaction line 500.00") is None

    def test_try_opening_balance_accepts_dr_suffix(self):
        assert try_opening_balance("Opening Balance 500.00 DR") == Decimal("500.00")

    def test_classify_amounts_maps_debit_credit_and_balance(self):
        debit, credit, balance = classify_amounts(["-", "10000.00", "55000.00"])

        assert debit is None
        assert credit == Decimal("10000.00")
        assert balance == Decimal("55000.00")

    def test_classify_amounts_handles_single_and_dual_token_shapes(self):
        assert classify_amounts(["7500.00"]) == (Decimal("7500.00"), None, None)
        assert classify_amounts(["3000.00", "47000.00"]) == (
            Decimal("3000.00"),
            None,
            Decimal("47000.00"),
        )

    def test_classify_amounts_handles_empty_and_comma_formats(self):
        assert classify_amounts([]) == (None, None, None)
        assert classify_amounts(["1,500.00", "-", "48,500.00"]) == (
            Decimal("1500.00"),
            None,
            Decimal("48500.00"),
        )

    def test_parse_txn_line_returns_savings_transaction_shape(self):
        result = parse_txn_line(
            "15/01/2024 UPI-PAYMENT 5,000.00 - 45,000.00",
            StatementType.SAVINGS,
        )

        assert result is not None
        assert result["date"] == date(2024, 1, 15)
        assert result["description"] == "UPI-PAYMENT"
        assert result["debit"] == Decimal("5000.00")
        assert result["balance"] == Decimal("45000.00")
        assert result["type"] == TransactionType.DEBIT

    def test_parse_txn_line_handles_value_date_and_cr_suffix(self):
        result = parse_txn_line(
            "15/01/2024 16/01/2024 NEFT TRANSFER 10,000.00 - 35,000.00 CR",
            StatementType.SAVINGS,
        )

        assert result is not None
        assert result["date"] == date(2024, 1, 15)
        assert result["debit"] == Decimal("10000.00")
        assert result["balance"] == Decimal("35000.00")

    def test_parse_txn_line_handles_credit_card_two_digit_year(self):
        result = parse_txn_line(
            "15/01/24 PURCHASE 500.00 49,500.00",
            StatementType.CREDIT_CARD,
        )

        assert result is not None
        assert result["date"].year == 2024
        assert result["debit"] == Decimal("500.00")

    def test_parse_txn_line_handles_serial_prefix_and_dash_date(self):
        result = parse_txn_line(
            "001 15-01-2024 ATM WITHDRAWAL 2,000.00 - 43,000.00",
            StatementType.SAVINGS,
        )

        assert result is not None
        assert result["date"] == date(2024, 1, 15)
        assert result["debit"] == Decimal("2000.00")

    def test_parse_txn_line_returns_none_for_non_transaction_text(self):
        assert parse_txn_line("Page 1 of 5", StatementType.SAVINGS) is None
        assert parse_txn_line("Account Statement", StatementType.SAVINGS) is None
        assert parse_txn_line("15/01/2024 Some description text only", StatementType.SAVINGS) is None