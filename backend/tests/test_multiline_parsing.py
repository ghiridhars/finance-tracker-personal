from datetime import date
from decimal import Decimal

from app.models.enums import TransactionType
from app.parsing.multiline_parsing import (
    infer_single_amount_direction,
    parse_amount_or_dash,
    try_parse_multiline_block,
)


class TestMultilineParsing:
    def test_try_parse_multiline_block_handles_comma_formatted_integer_amounts(self):
        """Amounts with Indian comma formatting but no decimal should be recognized."""
        lines = [
            "15/06/2025",
            "NEFT SALARY DEPOSIT",
            "5,000",
            "15,000 Cr",
        ]
        result = try_parse_multiline_block(lines, start=0, previous_balance=Decimal("10000"))
        assert result is not None
        assert result["data"]["credit"] == Decimal("5000")
        assert result["data"]["balance"] == Decimal("15000")

    def test_ml_amount_re_rejects_plain_long_digit_strings(self):
        """Plain digit strings without commas or decimals should not match _ML_AMOUNT_RE."""
        from app.parsing.multiline_parsing import _ML_AMOUNT_RE
        assert _ML_AMOUNT_RE.match("564314099684") is None
        assert _ML_AMOUNT_RE.match("56431409") is None
        assert _ML_AMOUNT_RE.match("5000") is None  # No structure = rejected
        # But these should match:
        assert _ML_AMOUNT_RE.match("5,000") is not None
        assert _ML_AMOUNT_RE.match("1,00,000") is not None
        assert _ML_AMOUNT_RE.match("5000.00") is not None
        assert _ML_AMOUNT_RE.match("1,00,320.00") is not None

    def test_parse_amount_or_dash_handles_dash_and_amounts(self):
        assert parse_amount_or_dash("-") is None
        assert parse_amount_or_dash("4006.44 Cr") == Decimal("4006.44")

    def test_parse_amount_or_dash_handles_indian_currency_formats(self):
        assert parse_amount_or_dash("1,12,206.68") == Decimal("112206.68")
        assert parse_amount_or_dash("₹500.00") == Decimal("500.00")
        assert parse_amount_or_dash("  42.50  ") == Decimal("42.50")
        assert parse_amount_or_dash("") is None

    def test_infer_single_amount_direction_uses_previous_balance(self):
        debit, credit = infer_single_amount_direction(
            amount=Decimal("54.00"),
            balance=Decimal("2006.44"),
            previous_balance=Decimal("1952.44"),
        )

        assert debit is None
        assert credit == Decimal("54.00")

    def test_try_parse_multiline_block_parses_single_amount_balance_block(self):
        lines = [
            "06-08-2021",
            "05570100013649:Int.Pd:01-05-2021 to",
            "31-07-2021",
            "54.00",
            "2006.44 Cr",
        ]

        result = try_parse_multiline_block(
            lines,
            start=0,
            previous_balance=Decimal("1952.44"),
        )

        assert result is not None
        assert result["next_index"] == 5
        data = result["data"]
        assert data["date"] == date(2021, 8, 6)
        assert data["credit"] == Decimal("54.00")
        assert data["balance"] == Decimal("2006.44")
        assert data["type"] == TransactionType.CREDIT

    def test_try_parse_multiline_block_parses_opening_balance_marker(self):
        lines = [
            "01-08-2021",
            "Opening Balance",
            "1952.44 Cr",
        ]

        result = try_parse_multiline_block(lines, start=0)

        assert result is not None
        assert result["next_index"] == 3
        assert result["data"] == {
            "kind": "opening_balance",
            "date": date(2021, 8, 1),
            "balance": Decimal("1952.44"),
        }

    def test_try_parse_multiline_block_handles_standalone_upi_ref_numbers(self):
        lines = [
            "04/10/2025",
            "UPI-JOHN DOE-9999999999@",
            "yescred-BARB0TRIVAN-564314099684-Pai",
            "d via CRED Value Dt 04/10/2025 Ref",
            "564314099684",
            "0.00",
            "20,000.00",
            "1,00,320.00",
        ]

        result = try_parse_multiline_block(lines, start=0)

        assert result is not None
        assert result["next_index"] == 8
        data = result["data"]
        assert data["date"] == date(2025, 10, 4)
        assert data["debit"] == Decimal("0.00")
        assert data["credit"] == Decimal("20000.00")
        assert data["balance"] == Decimal("100320.00")
        assert "564314099684" in data["description"]

    def test_try_parse_multiline_block_handles_dash_as_first_column(self):
        """Deposit row with '-' in the withdrawal column must not be silently dropped."""
        # 3-column: Withdrawal='-', Deposit=20000, Balance=1_00_320
        lines = [
            "04/10/2025",
            "NEFT CREDIT SALARY",
            "-",
            "20,000.00",
            "1,00,320.00",
        ]
        result = try_parse_multiline_block(lines, start=0, previous_balance=Decimal("80320"))
        assert result is not None, "Deposit row with dash in first column must not be dropped"
        data = result["data"]
        assert data["debit"] is None
        assert data["credit"] == Decimal("20000.00")
        assert data["balance"] == Decimal("100320.00")
        assert data["type"] == TransactionType.CREDIT

    def test_try_parse_multiline_block_handles_dash_as_credit_column(self):
        """Withdrawal row with '-' in the deposit column must parse correctly."""
        # 3-column: Withdrawal=500, Deposit='-', Balance=4500
        lines = [
            "05/10/2025",
            "POS AMAZON PURCHASE",
            "500.00",
            "-",
            "4,500.00",
        ]
        result = try_parse_multiline_block(lines, start=0, previous_balance=Decimal("5000"))
        assert result is not None
        data = result["data"]
        assert data["debit"] == Decimal("500.00")
        assert data["credit"] is None
        assert data["balance"] == Decimal("4500.00")
        assert data["type"] == TransactionType.DEBIT