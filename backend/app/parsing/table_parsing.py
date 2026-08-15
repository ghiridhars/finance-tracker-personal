import re

from app.models.enums import StatementType, TransactionType
from app.parsing.line_parsing import normalize_token_stream
from app.parsing.patterns import (
    get_cell,
    is_table_header as patterns_is_table_header,
    map_columns,
    parse_amount,
    parse_date,
    NOISE_PATTERN as _NOISE,
)


def expand_multiline_table_rows(
    rows: list[list[str | None]],
    col_map: dict,
) -> list[list[str | None]]:
    """Split rows where pdfplumber concatenated multiple transactions using newlines."""
    expanded: list[list[str | None]] = []
    date_idx = col_map.get("date")

    for row in rows:
        if date_idx is not None and date_idx < len(row) and row[date_idx] and "\n" in row[date_idx]:
            date_lines = [d.strip() for d in row[date_idx].split("\n") if d.strip()]
            if len(date_lines) > 1:
                split_cells = [(cell or "").split("\n") for cell in row]
                for i in range(len(date_lines)):
                    sub_row: list[str | None] = []
                    for lines in split_cells:
                        if i < len(lines):
                            sub_row.append(lines[i])
                        else:
                            sub_row.append("")
                    expanded.append(sub_row)
                continue
        expanded.append(row)

    return expanded


def filter_table_data_rows(
    rows: list[list[str | None]],
    col_map: dict,
) -> list[list[str | None]]:
    """Keep only rows that look like actual transaction records."""
    expanded_rows = expand_multiline_table_rows(rows, col_map)
    return [row for row in expanded_rows if looks_like_table_data_row(row, col_map)]


def looks_like_table_data_row(
    row: list[str | None],
    col_map: dict,
) -> bool:
    if not row or all(not (cell or "").strip() for cell in row):
        return False

    date_val = get_cell(row, col_map.get("date"))
    cleaned_date = date_val.replace("\n", " ").strip() if date_val else ""
    if not re.search(r"\d{2}[/-]\d{2}[/-]\d{2,4}", cleaned_date):
        return False

    has_amount = any(
        parse_amount(get_cell(row, col_map.get(field))) is not None
        for field in ("debit", "credit", "amount")
    )
    if not has_amount:
        return False

    description = get_cell(row, col_map.get("description"))
    normalized_description = description.replace("\n", " ").strip() if description else ""
    if is_table_metadata_row(normalized_description):
        return False

    return True


def map_table_columns(header_row: list[str | None]) -> dict[str, int | None]:
    return map_columns([(cell or "") for cell in header_row], include_value_date=True)


def parse_table_rows(
    rows: list[list[str | None]],
    col_map: dict,
    statement_type: StatementType,
) -> list[dict]:
    transactions: list[dict] = []

    for row in rows:
        if not row or all(not (cell or "").strip() for cell in row):
            continue

        date_val = get_cell(row, col_map["date"])
        date_val = date_val.replace("\n", " ").strip() if date_val else ""
        txn_date = parse_date(date_val)
        if txn_date is None:
            continue

        raw_desc = get_cell(row, col_map["description"])
        desc = normalize_token_stream(raw_desc.replace("\n", " ")) if raw_desc else ""
        if is_table_metadata_row(desc):
            continue

        ref = get_cell(row, col_map["reference"])
        ref = ref.replace("\n", " ").strip() if ref else None

        debit = parse_amount(get_cell(row, col_map["debit"]))
        credit = parse_amount(get_cell(row, col_map["credit"]))
        balance = parse_amount(get_cell(row, col_map["balance"]))

        if debit is None and credit is None and col_map["amount"] is not None:
            amount = parse_amount(get_cell(row, col_map["amount"]))
            if amount is not None:
                if amount < 0:
                    debit = abs(amount)
                else:
                    credit = amount

        if debit is None and credit is None:
            continue

        txn_type = TransactionType.DEBIT if (debit and debit > 0) else TransactionType.CREDIT

        transactions.append(
            {
                "date": txn_date,
                "description": desc or None,
                "reference": ref,
                "debit": debit,
                "credit": credit,
                "balance": balance,
                "type": txn_type,
            }
        )

    return transactions


def is_table_header_row(row: list[str | None]) -> bool:
    return patterns_is_table_header(row)


def is_table_metadata_row(description: str) -> bool:
    """Reject account-summary labels that table extraction can misread as transactions."""
    if not description:
        return False

    normalized = re.sub(r"\s+", " ", description).strip()
    if _NOISE.match(normalized):
        return True

    return bool(
        re.fullmatch(
            r"(?:ppf|savings|salary|current|term\s+deposit|fixed\s+deposit|recurring\s+deposit)\s+account",
            normalized,
            re.IGNORECASE,
        )
    )