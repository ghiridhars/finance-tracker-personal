import re
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsing.patterns import (
    DECIMAL_AMOUNT_RE,
    INTEGER_AMOUNT_RE,
    LEADING_DATE_RE,
    parse_amount,
    parse_date,
)


_MULTI_SPACE_RE = re.compile(r"\s+")
_UPI_AT_SPACE_HEAL_RE = re.compile(r"([\w._-]+)\s*@\s*([a-zA-Z0-9.-]+)", re.IGNORECASE)


def normalize_token_stream(raw_text: str | None) -> str | None:
    """
    Clean and normalize token stream at the parsing boundary:
    - Collapses consecutive whitespace.
    - Heals split `@` symbols and internal spaces in UPI handles (e.g., 'user @ hdfc' -> 'user@hdfc', 'virenderganes h84-1@okic' -> 'virenderganesh84-1@okic').
    - Strips non-printable ASCII control characters.
    """
    if not raw_text:
        return None
    clean = "".join(ch for ch in raw_text if ord(ch) >= 32)
    clean = _MULTI_SPACE_RE.sub(" ", clean).strip()

    if "@" in clean:
        match = re.search(r"(?:^|[/:])([^/:]*@[^/:]*)(?:[/:]|$)", clean)
        if match:
            raw_chunk = match.group(1)
            if " " in raw_chunk and raw_chunk.count(" ") <= 3:
                clean = clean.replace(raw_chunk, raw_chunk.replace(" ", ""))

    clean = _UPI_AT_SPACE_HEAL_RE.sub(r"\1@\2", clean)
    return clean or None


def try_opening_balance(line: str) -> Decimal | None:
    """Detect an opening-balance line and extract the balance value."""
    if "opening balance" not in line.lower():
        return None

    match = re.search(r"([\d,]+(?:\.\d{2})?)\s*(?:CR|DR)?\s*$", line, re.IGNORECASE)
    if match:
        return parse_amount(match.group(1))
    return None


def classify_amounts(
    tokens: list[str],
) -> tuple[Decimal | None, Decimal | None, Decimal | None]:
    """Map 1-3 trailing amount tokens to debit, credit, and balance."""
    if len(tokens) >= 3:
        debit_amount = parse_amount(tokens[-3])
        credit_amount = parse_amount(tokens[-2])
        balance_amount = parse_amount(tokens[-1])
        debit = debit_amount if debit_amount and debit_amount > 0 else None
        credit = credit_amount if credit_amount and credit_amount > 0 else None
        return debit, credit, balance_amount
    if len(tokens) == 2:
        amount = parse_amount(tokens[0])
        balance = parse_amount(tokens[1])
        return amount, None, balance
    if len(tokens) == 1:
        amount = parse_amount(tokens[0])
        return amount, None, None
    return None, None, None


def parse_txn_line(line: str, statement_type: StatementType) -> dict | None:
    """Parse a single transaction line into the shared raw transaction shape."""
    clean = re.sub(r"\s+(?:CR|DR)\s*$", "", line, flags=re.IGNORECASE).strip()

    match = LEADING_DATE_RE.match(clean)
    if not match:
        return None

    date_str = match.group(1)
    txn_date = parse_date(date_str)
    if txn_date is None:
        return None

    remaining = clean[match.end():].strip()

    value_date_match = re.match(r"(\d{2}[/-]\d{2}[/-]\d{2,4})\s*", remaining)
    if value_date_match:
        remaining = remaining[value_date_match.end():].strip()

    tokens = remaining.split()
    amount_tokens: list[str] = []
    found_decimal = False
    desc_end_idx = len(tokens)
    max_amounts = 3

    for index in range(len(tokens) - 1, -1, -1):
        if len(amount_tokens) >= max_amounts:
            break
        token = tokens[index]
        if DECIMAL_AMOUNT_RE.match(token):
            amount_tokens.insert(0, token)
            found_decimal = True
            desc_end_idx = index
        elif token == "-":
            amount_tokens.insert(0, "-")
            desc_end_idx = index
        elif (
            INTEGER_AMOUNT_RE.match(token)
            and len(token) <= 8
            and int(token.replace(",", "")) < 100_000_000
        ):
            amount_tokens.insert(0, token)
            desc_end_idx = index
        else:
            break

    min_amounts = 2 if statement_type == StatementType.SAVINGS else 1
    if len(amount_tokens) < min_amounts:
        return None
    if not found_decimal and len(amount_tokens) < 3:
        return None

    raw_description = " ".join(tokens[:desc_end_idx])
    description = normalize_token_stream(raw_description)
    debit, credit, balance = classify_amounts(amount_tokens)

    if debit is None and credit is None:
        return None

    txn_type = TransactionType.DEBIT if (debit and debit > 0) else TransactionType.CREDIT

    return {
        "date": txn_date,
        "description": description or None,
        "reference": None,
        "debit": debit,
        "credit": credit,
        "balance": balance,
        "type": txn_type,
    }