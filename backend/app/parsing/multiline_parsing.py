import re
from decimal import Decimal

from app.models.enums import TransactionType
from app.parsing.line_parsing import normalize_token_stream
from app.parsing.patterns import NOISE_PATTERN as _NOISE, parse_amount, parse_date

_ML_DATE_RE = re.compile(r"^\d{2}[/-]\d{2}[/-]\d{2,4}$")
_ML_SERIAL_RE = re.compile(r"^\d{1,4}$")
# Match amounts: decimal format (5000.00) OR Indian comma-formatted integer (5,000 / 1,00,000).
# Rejects plain long digit strings (UPI refs like 564314099684) which have no commas or decimals.
_ML_AMOUNT_RE = re.compile(r"^[\d,]+\.\d{1,2}$|^\d{1,3}(?:,\d{2,3})+$")
_ML_BALANCE_RE = re.compile(
    r"^(?:[\d,]+\.\d{1,2}|\d{1,3}(?:,\d{2,3})+)\s*(?:Cr|CR|cr|Dr|DR|dr)?$"
)
_ML_DASH_RE = re.compile(r"^-$")


def parse_amount_or_dash(text: str) -> Decimal | None:
    """Parse amount, treating '-' as None."""
    text = text.strip()
    if text == "-":
        return None
    return parse_amount(text)


def infer_single_amount_direction(
    *,
    amount: Decimal,
    balance: Decimal,
    previous_balance: Decimal | None,
) -> tuple[Decimal | None, Decimal | None]:
    if previous_balance is not None:
        if balance == previous_balance + amount:
            return None, amount
        if balance == previous_balance - amount:
            return amount, None
    return amount, None


def try_parse_multiline_block(
    lines: list[str],
    start: int,
    previous_balance: Decimal | None = None,
) -> dict | None:
    """Parse a multiline transaction or balance block starting at `start`."""
    index = start
    total_lines = len(lines)
    if index >= total_lines:
        return None

    line = lines[index]

    if _ML_SERIAL_RE.match(line):
        index += 1
        if index >= total_lines:
            return None

    if index >= total_lines or not _ML_DATE_RE.match(lines[index]):
        return None
    txn_date = parse_date(lines[index])
    if txn_date is None:
        return None
    index += 1

    if index < total_lines and _ML_DATE_RE.match(lines[index]):
        index += 1

    if index < total_lines and lines[index].lower() in {"opening balance", "closing balance"}:
        kind = lines[index].lower().replace(" ", "_")
        index += 1
        if index >= total_lines:
            return None
        balance = parse_amount(lines[index])
        if balance is None:
            return None
        return {
            "data": {"kind": kind, "date": txn_date, "balance": balance},
            "next_index": index + 1,
        }

    description_lines: list[str] = []
    while index < total_lines:
        current = lines[index]
        if _ML_AMOUNT_RE.match(current) or _ML_BALANCE_RE.match(current) or _ML_DASH_RE.match(current):
            break
        if _ML_SERIAL_RE.match(current) and index + 1 < total_lines and _ML_DATE_RE.match(lines[index + 1]):
            break
        if _NOISE.search(current):
            break
        if not current:
            break
        description_lines.append(current)
        index += 1

    raw_desc = " ".join(description_lines).strip()
    description = normalize_token_stream(raw_desc) or ""

    if index >= total_lines:
        return None

    # first_amount may be None when the cell is "-" (3-column layout: debit | credit | balance).
    # Do NOT abort here — read all three cells first, then decide.
    first_line = lines[index]
    first_is_dash = _ML_DASH_RE.match(first_line.strip()) is not None
    first_amount = parse_amount_or_dash(first_line)
    # If it's not a dash and not a valid amount, this is not an amount line → abort.
    if first_amount is None and not first_is_dash:
        return None
    index += 1

    if index >= total_lines:
        return None
    second_amount = parse_amount_or_dash(lines[index])
    index += 1

    next_value = parse_amount(lines[index]) if index < total_lines else None
    if next_value is not None:
        # 3-column row: debit | credit | balance
        debit = first_amount   # None when first cell was "-"
        credit = second_amount  # None when second cell was "-"
        balance = next_value
        index += 1
        if debit is None and credit is None:
            return None
    else:
        # 2-column row: single_amount | balance
        # This branch requires a real amount in first_amount; dash-only rows can't be inferred.
        if first_amount is None:
            return None
        balance = second_amount
        if balance is None:
            return None
        debit, credit = infer_single_amount_direction(
            amount=first_amount,
            balance=balance,
            previous_balance=previous_balance,
        )

    txn_type = TransactionType.DEBIT if (debit and debit > 0) else TransactionType.CREDIT

    return {
        "data": {
            "date": txn_date,
            "description": description or None,
            "reference": None,
            "debit": debit,
            "credit": credit,
            "balance": balance,
            "type": txn_type,
        },
        "next_index": index,
    }