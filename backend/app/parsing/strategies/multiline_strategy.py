import re
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.parsing.patterns import NOISE_PATTERN as _NOISE, parse_amount, parse_date
from app.parsing.extraction.artifacts import ExtractedTextDocument, ensure_text_document
from app.parsing.line_parsing import try_opening_balance
from app.parsing.multiline_parsing import try_parse_multiline_block
from app.parsing.result_builders import build_credit_card_result, build_result

_ML_DATE_RE = re.compile(r"^\d{2}[/-]\d{2}[/-]\d{2,4}$")

# Date with pipe+time: "18/01/2026| 14:34" or "18/01/2026 | 14:34"
# Also matches "18/01/2026 14:34:56" (space-separated time, no pipe)
_CC_DATE_TIME_RE = re.compile(
    r"^(\d{2}[/-]\d{2}[/-]\d{2,4})\s*(?:\||\s)\s*\d{2}:\d{2}"
)
# Amount line: optional "+" then currency symbol/letter then amount
# e.g., " C 245.00", "+  C 26,317.00", "+ ₹ 245.00"
_CC_AMOUNT_RE = re.compile(r"^(\+)?\s*[C₹$]\s*([\d,]+\.\d{2})$")

# Standalone date line (with optional time component)
_CC_SIMPLE_DATE_RE = re.compile(
    r"^(\d{2}[/-]\d{2}[/-]\d{2,4})(?:\s+\d{2}:\d{2}(?::\d{2})?)?$"
)
# Amount with optional Cr suffix: "948.00", "8,779.00 Cr"
_CC_SIMPLE_AMOUNT_RE = re.compile(r"^([\d,]+\.\d{2})\s*(?:(Cr|CR|cr))?\s*$")


def try_multiline_strategy(
    text: ExtractedTextDocument | str,
    statement_type: StatementType,
) -> ParseResult | None:
    document = ensure_text_document(text)
    lines = list(document.stripped_lines)

    date_lines = sum(1 for line in lines if _ML_DATE_RE.match(line))
    if date_lines < 3:
        return None

    transactions: list[dict] = []
    opening_balance: Decimal | None = None
    previous_balance: Decimal | None = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if not line or _NOISE.search(line):
            i += 1
            continue

        ob = try_opening_balance(line)
        if ob is not None:
            if opening_balance is None:
                opening_balance = ob
                previous_balance = ob
            i += 1
            continue

        txn = try_parse_multiline_block(lines, i, previous_balance)
        if txn:
            txn_data = txn["data"]
            if txn_data.get("kind") == "opening_balance":
                if opening_balance is None:
                    opening_balance = txn_data["balance"]
                    previous_balance = txn_data["balance"]
            elif txn_data.get("kind") == "closing_balance":
                previous_balance = txn_data["balance"]
                if transactions:
                    break
            else:
                transactions.append(txn_data)
                if txn_data.get("balance") is not None:
                    previous_balance = txn_data["balance"]
            i = txn["next_index"]
        else:
            i += 1

    if not transactions:
        return None

    # Back-calculate opening balance if not explicitly found.
    # We intentionally do NOT mutate the first transaction's direction here:
    # the block parser already inferred debit/credit using previous_balance=None
    # (defaulting to debit), which may be wrong, but correcting it would require
    # verifying bal == opening_balance ± amount — a circular dependency.
    # Providing a back-calculated opening_balance is still useful for audit purposes.
    if opening_balance is None and transactions:
        first = transactions[0]
        bal = first.get("balance")
        if bal is not None:
            d = first.get("debit") or Decimal("0")
            c = first.get("credit") or Decimal("0")
            opening_balance = bal + d - c

    return build_result(transactions, statement_type, opening_balance)


def try_cc_multiline_strategy(
    text: ExtractedTextDocument | str,
) -> ParseResult | None:
    document = ensure_text_document(text)
    lines = list(document.stripped_lines)

    date_time_count = sum(1 for line in lines if _CC_DATE_TIME_RE.match(line))
    if date_time_count < 2:
        return None

    transactions: list[dict] = []
    i = 0

    while i < len(lines):
        line = lines[i]

        match = _CC_DATE_TIME_RE.match(line)
        if not match:
            i += 1
            continue

        txn_date = parse_date(match.group(1))
        if txn_date is None:
            i += 1
            continue
        i += 1

        desc_lines: list[str] = []
        is_credit = False
        amount: Decimal | None = None
        ref: str | None = None

        while i < len(lines):
            current = lines[i]

            amount_match = _CC_AMOUNT_RE.match(current)
            if amount_match:
                is_credit = amount_match.group(1) == "+"
                amount = parse_amount(amount_match.group(2))
                i += 1
                if i < len(lines) and len(lines[i].strip()) <= 2:
                    i += 1
                break

            if _CC_DATE_TIME_RE.match(current):
                break

            if _NOISE.search(current):
                i += 1
                continue

            ref_match = re.search(r"\(Ref#\s*([^)]+)\)", current)
            if ref_match:
                ref = ref_match.group(1).strip()

            if current and current != "l":
                desc_lines.append(current)
            i += 1

        if amount is None or amount <= 0:
            continue

        description = " ".join(desc_lines).strip()
        if description.startswith("EMI "):
            description = description[4:].strip()

        txn_type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT
        transactions.append(
            {
                "date": txn_date,
                "description": description or None,
                "reference": ref,
                "debit": amount if not is_credit else None,
                "credit": amount if is_credit else None,
                "balance": None,
                "type": txn_type,
            }
        )

    if not transactions:
        return None

    return build_credit_card_result(transactions)


def try_cc_simple_multiline_strategy(
    text: ExtractedTextDocument | str,
) -> ParseResult | None:
    document = ensure_text_document(text)
    lines = list(document.stripped_lines)

    date_line_count = sum(1 for line in lines if _CC_SIMPLE_DATE_RE.match(line))
    if date_line_count < 3:
        return None

    transactions: list[dict] = []
    i = 0

    while i < len(lines):
        line = lines[i]

        date_match = _CC_SIMPLE_DATE_RE.match(line)
        if not date_match:
            i += 1
            continue

        txn_date = parse_date(date_match.group(1))
        if txn_date is None:
            i += 1
            continue
        i += 1

        desc_lines: list[str] = []
        is_credit = False
        amount: Decimal | None = None
        ref: str | None = None

        while i < len(lines):
            current = lines[i]

            if not current:
                i += 1
                continue

            amount_match = _CC_SIMPLE_AMOUNT_RE.match(current)
            if amount_match:
                amount = parse_amount(amount_match.group(1))
                is_credit = amount_match.group(2) is not None
                i += 1
                break

            if _CC_SIMPLE_DATE_RE.match(current):
                break

            if _NOISE.search(current):
                i += 1
                continue

            lower = current.lower()
            if any(
                keyword in lower
                for keyword in (
                    "reward points",
                    "opening balance",
                    "closing balance",
                    "cash points",
                    "important information",
                    "total dues",
                    "payment due",
                    "credit limit",
                )
            ):
                amount = None
                break

            ref_match = re.search(r"\(Ref#\s*([^)]+)\)", current)
            if ref_match:
                ref = ref_match.group(1).strip()

            desc_lines.append(current)
            i += 1

        if amount is None or amount <= 0:
            continue

        description = " ".join(desc_lines).strip()
        if not description:
            continue

        txn_type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT
        transactions.append(
            {
                "date": txn_date,
                "description": description or None,
                "reference": ref,
                "debit": amount if not is_credit else None,
                "credit": amount if is_credit else None,
                "balance": None,
                "type": txn_type,
            }
        )

    if not transactions:
        return None

    return build_credit_card_result(transactions)