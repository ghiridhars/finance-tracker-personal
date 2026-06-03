import re

from app.models.enums import StatementType
from app.parsers.base_parser import ParseResult
from app.parsing.patterns import NOISE_PATTERN as _NOISE
from app.parsing.extraction.artifacts import ExtractedTextDocument, ensure_text_document
from app.parsing.line_parsing import parse_txn_line, try_opening_balance
from app.parsing.result_builders import build_result


def try_single_line_strategy(
    text: ExtractedTextDocument | str,
    statement_type: StatementType,
) -> ParseResult | None:
    document = ensure_text_document(text)
    raw_txns: list[dict] = []
    current: dict | None = None
    opening_balance = None

    for line in document.raw_lines:
        stripped = line.strip()
        if not stripped:
            continue

        if _NOISE.search(stripped):
            continue

        opening = try_opening_balance(stripped)
        if opening is not None:
            opening_balance = opening
            continue

        txn = parse_txn_line(stripped, statement_type)
        if txn:
            if current:
                raw_txns.append(current)
            current = txn
            continue

        if current and not _NOISE.search(stripped):
            previous = current.get("description") or ""
            current["description"] = (previous + " " + stripped).strip()

    if current:
        raw_txns.append(current)

    if not raw_txns:
        return None

    for txn in raw_txns:
        if txn.get("description"):
            txn["description"] = re.sub(r"\s+", " ", txn["description"]).strip()

    return build_result(raw_txns, statement_type, opening_balance)