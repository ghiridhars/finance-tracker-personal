"""
Generic CSV/Excel statement parser.

Handles CSV and Excel files from any bank by auto-detecting column mappings.
Supports common column names across Indian banks:
  - Date, Txn Date, Transaction Date, Value Date, Posting Date
  - Description, Narration, Particulars, Details, Remarks
  - Debit, Withdrawal, Dr, Amount (Debit)
  - Credit, Deposit, Cr, Amount (Credit)
  - Balance, Closing Balance, Running Balance
  - Reference, Ref No, Txn Ref, Chq/Ref No
"""
import csv
import io
import logging
import re
from datetime import datetime, date
from decimal import Decimal, InvalidOperation
from typing import Optional

from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)

logger = logging.getLogger(__name__)

# ── Column name patterns (case-insensitive) ───────────────────

DATE_PATTERNS = [
    r"^date$", r"txn\s*date", r"transaction\s*date", r"value\s*date",
    r"posting\s*date", r"^dt$",
]

DESCRIPTION_PATTERNS = [
    r"description", r"narration", r"particulars", r"details",
    r"remarks", r"transaction\s*details",
]

DEBIT_PATTERNS = [
    r"^debit$", r"withdrawal", r"^dr$", r"amount\s*\(?\s*debit\s*\)?",
    r"debit\s*amount",
]

CREDIT_PATTERNS = [
    r"^credit$", r"deposit", r"^cr$", r"amount\s*\(?\s*credit\s*\)?",
    r"credit\s*amount",
]

AMOUNT_PATTERNS = [
    r"^amount$", r"transaction\s*amount", r"txn\s*amount",
]

BALANCE_PATTERNS = [
    r"balance", r"closing\s*balance", r"running\s*balance",
    r"available\s*balance",
]

REFERENCE_PATTERNS = [
    r"reference", r"ref\s*no", r"txn\s*ref", r"chq.*ref",
    r"utr", r"transaction\s*id",
]

# Common date formats across Indian bank CSVs
DATE_FORMATS = [
    "%d/%m/%Y", "%d-%m-%Y", "%d/%m/%y", "%d-%m-%y",
    "%Y-%m-%d", "%d %b %Y", "%d %b %y", "%d-%b-%Y",
    "%d-%b-%y", "%m/%d/%Y", "%d %B %Y",
]


def parse_csv(
    content: bytes,
    bank: BankType,
    statement_type: StatementType,
) -> ParseResult:
    """
    Parse a CSV file into the appropriate statement schema.
    Auto-detects column mappings and date formats.
    """
    try:
        # Decode CSV (try utf-8, then latin-1 as fallback)
        try:
            text = content.decode("utf-8-sig")  # BOM-aware
        except UnicodeDecodeError:
            text = content.decode("latin-1")

        # Detect delimiter (comma, tab, semicolon, pipe)
        sample = text[:2000]
        delimiter = _detect_delimiter(sample)

        reader = csv.reader(io.StringIO(text), delimiter=delimiter)
        rows = list(reader)

        if len(rows) < 2:
            return ParseResult.failure("CSV file has fewer than 2 rows (need header + data)")

        # Find header row (skip blank rows or bank metadata)
        header_idx, headers = _find_header_row(rows)
        if header_idx is None:
            return ParseResult.failure(
                "Could not detect column headers in the CSV. "
                "Expected columns like: Date, Description, Debit, Credit, Balance"
            )

        data_rows = rows[header_idx + 1:]
        logger.info(
            f"CSV parsing: {len(data_rows)} data rows, "
            f"delimiter='{delimiter}', headers={headers}"
        )

        # Map columns
        col_map = _map_columns(headers)
        logger.info(f"Column mapping: {col_map}")

        if col_map.get("date") is None:
            return ParseResult.failure("Could not find a Date column in the CSV")

        # Parse rows into transactions
        if statement_type == StatementType.CREDIT_CARD:
            return _parse_as_credit_card(data_rows, col_map, headers, bank)
        else:
            return _parse_as_savings(data_rows, col_map, headers, bank)

    except Exception as e:
        logger.error(f"CSV parse failed: {e}", exc_info=True)
        return ParseResult.failure(f"CSV parse failed: {e}")


def _detect_delimiter(sample: str) -> str:
    """Auto-detect CSV delimiter."""
    counts = {
        ",": sample.count(","),
        "\t": sample.count("\t"),
        ";": sample.count(";"),
        "|": sample.count("|"),
    }
    return max(counts, key=counts.get)


def _find_header_row(rows: list[list[str]]) -> tuple[Optional[int], list[str]]:
    """
    Find the header row by looking for rows containing date/description-like columns.
    Banks often put metadata (bank name, account no) in the first few rows.
    """
    for i, row in enumerate(rows[:10]):  # Check first 10 rows
        row_text = " ".join(col.strip().lower() for col in row)
        has_date = any(re.search(p, row_text) for p in DATE_PATTERNS)
        has_desc = any(re.search(p, row_text) for p in DESCRIPTION_PATTERNS)
        has_amount = (
            any(re.search(p, row_text) for p in DEBIT_PATTERNS)
            or any(re.search(p, row_text) for p in CREDIT_PATTERNS)
            or any(re.search(p, row_text) for p in AMOUNT_PATTERNS)
        )
        if has_date and (has_desc or has_amount):
            return i, [col.strip() for col in row]
    return None, []


def _map_columns(headers: list[str]) -> dict[str, Optional[int]]:
    """Map header names to column indices using pattern matching."""
    mapping: dict[str, Optional[int]] = {
        "date": None,
        "description": None,
        "debit": None,
        "credit": None,
        "amount": None,
        "balance": None,
        "reference": None,
    }

    for idx, header in enumerate(headers):
        h = header.strip().lower()
        if not h:
            continue

        for pattern in DATE_PATTERNS:
            if re.search(pattern, h) and mapping["date"] is None:
                mapping["date"] = idx
                break
        for pattern in DESCRIPTION_PATTERNS:
            if re.search(pattern, h) and mapping["description"] is None:
                mapping["description"] = idx
                break
        for pattern in DEBIT_PATTERNS:
            if re.search(pattern, h) and mapping["debit"] is None:
                mapping["debit"] = idx
                break
        for pattern in CREDIT_PATTERNS:
            if re.search(pattern, h) and mapping["credit"] is None:
                mapping["credit"] = idx
                break
        for pattern in AMOUNT_PATTERNS:
            if re.search(pattern, h) and mapping["amount"] is None:
                mapping["amount"] = idx
                break
        for pattern in BALANCE_PATTERNS:
            if re.search(pattern, h) and mapping["balance"] is None:
                mapping["balance"] = idx
                break
        for pattern in REFERENCE_PATTERNS:
            if re.search(pattern, h) and mapping["reference"] is None:
                mapping["reference"] = idx
                break

    return mapping


def _parse_amount(value: str) -> Optional[Decimal]:
    """Parse an amount string, stripping currency symbols and commas."""
    if not value or not value.strip():
        return None
    cleaned = re.sub(r"[₹$€£,\s]", "", value.strip())
    cleaned = cleaned.replace("(", "-").replace(")", "")  # (1000) → -1000
    if not cleaned or cleaned == "-":
        return None
    try:
        return Decimal(cleaned)
    except InvalidOperation:
        return None


def _parse_csv_date(value: str) -> Optional[date]:
    """Try multiple date formats to parse a date string."""
    if not value or not value.strip():
        return None
    value = value.strip()
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None


def _get_cell(row: list[str], idx: Optional[int]) -> str:
    """Safely get a cell value by index."""
    if idx is None or idx >= len(row):
        return ""
    return row[idx].strip()


def _parse_as_savings(
    rows: list[list[str]],
    col_map: dict,
    headers: list[str],
    bank: BankType,
) -> ParseResult:
    """Parse CSV rows as a savings account statement."""
    statement = SavingsAccountStatementSchema()
    statement.account_holder_name = f"{bank.value} Account"

    min_date = None
    max_date = None
    first_balance = None
    last_balance = None

    for row in rows:
        if not row or all(not c.strip() for c in row):
            continue

        txn_date = _parse_csv_date(_get_cell(row, col_map["date"]))
        if txn_date is None:
            continue  # Skip rows without a valid date

        description = _get_cell(row, col_map["description"])
        reference = _get_cell(row, col_map["reference"])
        debit = _parse_amount(_get_cell(row, col_map["debit"]))
        credit = _parse_amount(_get_cell(row, col_map["credit"]))
        balance = _parse_amount(_get_cell(row, col_map["balance"]))

        # If only a single "amount" column exists, determine type from sign
        if debit is None and credit is None and col_map["amount"] is not None:
            amount = _parse_amount(_get_cell(row, col_map["amount"]))
            if amount is not None:
                if amount < 0:
                    debit = abs(amount)
                else:
                    credit = amount

        # Determine transaction type
        if debit and debit > 0:
            txn_type = TransactionType.DEBIT
        elif credit and credit > 0:
            txn_type = TransactionType.CREDIT
        else:
            continue  # Skip rows with no amount

        txn = SavingsAccountTransactionSchema(
            date=txn_date,
            description=description or None,
            reference_number=reference or None,
            withdrawal_amount=debit,
            deposit_amount=credit,
            closing_balance=balance,
            type=txn_type,
        )
        statement.transactions.append(txn)

        # Track date range and balances
        if min_date is None or txn_date < min_date:
            min_date = txn_date
        if max_date is None or txn_date > max_date:
            max_date = txn_date
        if balance is not None:
            if first_balance is None:
                first_balance = balance
            last_balance = balance

    if not statement.transactions:
        return ParseResult.failure("No transactions found in CSV")

    statement.from_date = min_date
    statement.to_date = max_date
    if first_balance is not None:
        # Opening balance = first closing balance ± first transaction
        txn0 = statement.transactions[0]
        if txn0.withdrawal_amount:
            statement.opening_balance = first_balance + txn0.withdrawal_amount
        elif txn0.deposit_amount:
            statement.opening_balance = first_balance - txn0.deposit_amount
        else:
            statement.opening_balance = first_balance
    statement.closing_balance = last_balance

    logger.info(f"CSV savings parse: {len(statement.transactions)} transactions")
    return ParseResult.ok(statement)


def _parse_as_credit_card(
    rows: list[list[str]],
    col_map: dict,
    headers: list[str],
    bank: BankType,
) -> ParseResult:
    """Parse CSV rows as a credit card statement."""
    statement = CreditCardStatementSchema()
    statement.card_holder_name = f"{bank.value} Card"

    min_date = None
    max_date = None

    for row in rows:
        if not row or all(not c.strip() for c in row):
            continue

        txn_date = _parse_csv_date(_get_cell(row, col_map["date"]))
        if txn_date is None:
            continue

        description = _get_cell(row, col_map["description"])
        reference = _get_cell(row, col_map["reference"])
        debit = _parse_amount(_get_cell(row, col_map["debit"]))
        credit = _parse_amount(_get_cell(row, col_map["credit"]))

        # Single amount column
        if debit is None and credit is None and col_map["amount"] is not None:
            amount = _parse_amount(_get_cell(row, col_map["amount"]))
            if amount is not None:
                if amount < 0:
                    credit = abs(amount)
                else:
                    debit = amount

        if debit and debit > 0:
            txn_type = TransactionType.DEBIT
            amount = debit
        elif credit and credit > 0:
            txn_type = TransactionType.CREDIT
            amount = credit
        else:
            continue

        txn = CreditCardTransactionSchema(
            date=txn_date,
            description=description or None,
            amount=amount,
            type=txn_type,
            reference_number=reference or None,
        )
        statement.transactions.append(txn)

        if min_date is None or txn_date < min_date:
            min_date = txn_date
        if max_date is None or txn_date > max_date:
            max_date = txn_date

    if not statement.transactions:
        return ParseResult.failure("No transactions found in CSV")

    statement.statement_date = max_date

    logger.info(f"CSV credit card parse: {len(statement.transactions)} transactions")
    return ParseResult.ok(statement)
