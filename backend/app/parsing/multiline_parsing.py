import re
from decimal import Decimal

from app.models.enums import TransactionType
from app.parsing.patterns import NOISE_PATTERN as _NOISE, parse_amount, parse_date

_ML_DATE_RE = re.compile(r"^\d{2}[/-]\d{2}[/-]\d{2,4}$")
_ML_SERIAL_RE = re.compile(r"^\d{1,4}$")
_ML_AMOUNT_RE = re.compile(r"^[\d,]+(?:\.\d{1,2})?$")
_ML_BALANCE_RE = re.compile(r"^[\d,]+(?:\.\d{1,2})?\s*(?:Cr|CR|cr|Dr|DR|dr)?$")
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

    description = " ".join(description_lines).strip()

    if index >= total_lines:
        return None
    first_amount = parse_amount_or_dash(lines[index])
    if first_amount is None:
        return None
    index += 1

    if index >= total_lines:
        return None
    second_amount = parse_amount_or_dash(lines[index])
    index += 1

    next_value = parse_amount(lines[index]) if index < total_lines else None
    if next_value is not None:
        debit = first_amount
        credit = second_amount
        balance = next_value
        index += 1
        if debit is None and credit is None:
            return None
    else:
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