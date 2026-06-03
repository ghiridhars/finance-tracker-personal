from datetime import date
from decimal import Decimal

from app.models.enums import TransactionType
from app.parsing.multiline_parsing import (
    infer_single_amount_direction,
    parse_amount_or_dash,
    try_parse_multiline_block,
)


class TestMultilineParsing:
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