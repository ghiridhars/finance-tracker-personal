from datetime import date
from decimal import Decimal

from app.models.enums import StatementType
from app.parsing.table_parsing import (
    expand_multiline_table_rows,
    filter_table_data_rows,
    is_table_metadata_row,
    map_table_columns,
    parse_table_rows,
)


class TestExpandMultilineTableRows:
    def test_splits_rows_with_newline_joined_dates(self):
        rows = [
            ["01/05/2026\n02/05/2026", "UPI PAYMENT\nNEFT SALARY", "500\n0", "0\n10000", "4500\n14500"],
        ]
        col_map = {"date": 0, "description": 1, "debit": 2, "credit": 3, "balance": 4}
        expanded = expand_multiline_table_rows(rows, col_map)
        assert len(expanded) == 2
        assert expanded[0][0] == "01/05/2026"
        assert expanded[1][0] == "02/05/2026"
        assert expanded[0][1] == "UPI PAYMENT"
        assert expanded[1][1] == "NEFT SALARY"

    def test_preserves_single_line_rows(self):
        rows = [["01/05/2026", "UPI PAYMENT", "500", "0", "4500"]]
        col_map = {"date": 0}
        expanded = expand_multiline_table_rows(rows, col_map)
        assert expanded == rows

    def test_handles_uneven_newline_counts_across_columns(self):
        rows = [
            ["01/05/2026\n02/05/2026", "LINE1\nLINE2\nLINE3", "500\n600", "", "4500\n3900"],
        ]
        col_map = {"date": 0, "description": 1, "debit": 2, "credit": 3, "balance": 4}
        expanded = expand_multiline_table_rows(rows, col_map)
        assert len(expanded) == 2
        assert expanded[0][1] == "LINE1"
        assert expanded[1][1] == "LINE2"

    def test_no_expansion_when_date_column_has_no_newlines(self):
        rows = [["01/05/2026", "LINE1\nLINE2", "500", "0", "4500"]]
        col_map = {"date": 0, "description": 1}
        expanded = expand_multiline_table_rows(rows, col_map)
        assert len(expanded) == 1

    def test_handles_none_cells(self):
        rows = [[None, None, None]]
        col_map = {"date": 0}
        expanded = expand_multiline_table_rows(rows, col_map)
        assert len(expanded) == 1


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