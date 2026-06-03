from datetime import date
from decimal import Decimal

from app.models.enums import StatementType
from app.parsing.table_parsing import (
    filter_table_data_rows,
    is_table_metadata_row,
    map_table_columns,
    parse_table_rows,
)


class TestTableParsing:
    def test_is_table_metadata_row_rejects_account_summary_labels(self):
        assert is_table_metadata_row("SAVINGS ACCOUNT") is True
        assert is_table_metadata_row("TERM DEPOSIT ACCOUNT") is True
        assert is_table_metadata_row("UPI PAYMENT TO MERCHANT") is False

    def test_filter_table_data_rows_keeps_transaction_rows_only(self):
        rows = [
            ["01/05/2026", "SAVINGS ACCOUNT", "", "1", "", "5000"],
            ["", "", "", "", "", ""],
            ["15/10/2018", "UPI PAYMENT", "", "30", "", "4970"],
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

        filtered = filter_table_data_rows(rows, col_map)

        assert filtered == [["15/10/2018", "UPI PAYMENT", "", "30", "", "4970"]]

    def test_map_table_columns_preserves_value_date_support(self):
        col_map = map_table_columns(
            ["DATE", "VALUE DATE", "NARRATION", "DEPOSIT (CR)", "BALANCE"]
        )

        assert col_map["date"] == 0
        assert col_map["description"] == 2
        assert col_map["credit"] == 3
        assert col_map["balance"] == 4

    def test_parse_table_rows_supports_single_amount_column_sign(self):
        rows = [["15/10/2018", "UPI REFUND", "REF1", "250.00", "7500.00"]]
        col_map = {
            "date": 0,
            "description": 1,
            "reference": 2,
            "debit": None,
            "credit": None,
            "amount": 3,
            "balance": 4,
        }

        transactions = parse_table_rows(rows, col_map, StatementType.SAVINGS)

        assert len(transactions) == 1
        assert transactions[0]["date"] == date(2018, 10, 15)
        assert transactions[0]["credit"] == Decimal("250.00")
        assert transactions[0]["balance"] == Decimal("7500.00")

    def test_parse_table_rows_skips_account_summary_rows(self):
        rows = [
            ["01/05/2026", "SAVINGS ACCOUNT", "", "1", "", "5000"],
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

        transactions = parse_table_rows(rows, col_map, StatementType.SAVINGS)

        assert len(transactions) == 1
        assert transactions[0]["date"] == date(2018, 10, 15)
        assert transactions[0]["description"].startswith("UPI/")
        assert transactions[0]["debit"] == Decimal("30")