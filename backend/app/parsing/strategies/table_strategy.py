import logging

from app.models.enums import StatementType
from app.parsers.base_parser import ParseResult
from app.parsing.extraction.artifacts import ExtractedPageTables
from app.parsing.result_builders import build_result
from app.parsing.table_parsing import (
    filter_table_data_rows,
    is_table_header_row,
    map_table_columns,
    parse_table_rows,
)

logger = logging.getLogger(__name__)


def try_table_strategy(
    page_tables: list[ExtractedPageTables],
    statement_type: StatementType,
) -> ParseResult | None:
    col_map: dict | None = None
    all_data_rows: list[list[str]] = []

    for page in page_tables:
        for table in page.tables:
            if not table:
                continue

            appended_rows = False
            for i, row in enumerate(table):
                if is_table_header_row(row):
                    new_map = map_table_columns(row)
                    if new_map.get("date") is not None and (
                        new_map.get("debit") is not None
                        or new_map.get("credit") is not None
                        or new_map.get("amount") is not None
                    ):
                        if col_map is None:
                            col_map = new_map
                        all_data_rows.extend(
                            filter_table_data_rows(
                                table[i + 1 :],
                                col_map,
                            )
                        )
                        appended_rows = True
                        break

            if not appended_rows and col_map is not None:
                all_data_rows.extend(filter_table_data_rows(table, col_map))

    if col_map is None or not all_data_rows:
        return None

    logger.info("Table strategy: col_map=%s, %s data rows", col_map, len(all_data_rows))
    transactions = parse_table_rows(all_data_rows, col_map, statement_type)

    if not transactions:
        return None

    return build_result(transactions, statement_type)