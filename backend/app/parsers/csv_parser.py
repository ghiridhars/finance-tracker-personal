"""
Generic CSV/Excel statement parser.

Handles CSV, TSV, and Excel (.xlsx/.xls) files from any bank by
auto-detecting column mappings.

Supports common column names across Indian banks:
  - Date, Txn Date, Transaction Date, Value Date, Posting Date
  - Description, Narration, Particulars, Details, Remarks
  - Debit, Withdrawal, Dr, Amount (Debit)
  - Credit, Deposit, Cr, Amount (Credit)
  - Balance, Closing Balance, Running Balance
  - Reference, Ref No, Txn Ref, Chq/Ref No

Uses:
  - pandas for reading CSV/Excel into a DataFrame
  - charset-normalizer for encoding detection
  - python-dateutil (via patterns.parse_date) for robust date parsing
"""
import io
import logging
from datetime import date
from decimal import Decimal
from typing import Optional

import pandas as pd

from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.parsers.patterns import (
    parse_date,
    parse_amount,
    map_columns,
    detect_encoding,
    is_table_header,
)
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)

logger = logging.getLogger(__name__)


def parse_csv(
    content: bytes,
    bank: BankType,
    statement_type: StatementType,
    filename: str = "upload.csv",
) -> ParseResult:
    """
    Parse a CSV or Excel file into the appropriate statement schema.
    Auto-detects column mappings, delimiters, encoding, and date formats.
    """
    try:
        df = _read_to_dataframe(content, filename)

        if len(df) < 2:
            return ParseResult.failure("File has fewer than 2 rows (need header + data)")

        # Find header row (skip blank rows or bank metadata)
        header_idx, headers = _find_header_row_in_df(df)
        if header_idx is None:
            return ParseResult.failure(
                "Could not detect column headers. "
                "Expected columns like: Date, Description, Debit, Credit, Balance"
            )

        # Data rows start after the header
        data_df = df.iloc[header_idx + 1:].reset_index(drop=True)
        logger.info(
            f"Parsing: {len(data_df)} data rows, headers={headers}"
        )

        # Map columns using shared patterns
        col_map = map_columns(headers)
        logger.info(f"Column mapping: {col_map}")

        if col_map.get("date") is None:
            return ParseResult.failure("Could not find a Date column")

        if statement_type == StatementType.CREDIT_CARD:
            return _parse_as_credit_card(data_df, col_map, bank)
        else:
            return _parse_as_savings(data_df, col_map, bank)

    except Exception as e:
        logger.error(f"CSV/Excel parse failed: {e}", exc_info=True)
        return ParseResult.failure(f"Parse failed: {e}")


def _read_to_dataframe(content: bytes, filename: str) -> pd.DataFrame:
    """
    Read CSV or Excel content into a pandas DataFrame.
    Auto-detects encoding for CSV and handles .xlsx/.xls natively.
    """
    lower = filename.lower()

    if lower.endswith((".xlsx", ".xls")):
        engine = "openpyxl" if lower.endswith(".xlsx") else None
        return pd.read_excel(
            io.BytesIO(content),
            engine=engine,
            header=None,
            dtype=str,
        )

    # CSV/TSV — detect encoding first
    encoding = detect_encoding(content)
    logger.info(f"Detected encoding: {encoding}")

    try:
        sample = content.decode(encoding, errors="replace")[:2000]
    except (UnicodeDecodeError, LookupError):
        sample = content.decode("utf-8", errors="replace")[:2000]
        encoding = "utf-8"

    counts = {
        ",": sample.count(","),
        "\t": sample.count("\t"),
        ";": sample.count(";"),
        "|": sample.count("|"),
    }
    delimiter = max(counts, key=counts.get)
    logger.info(f"Detected delimiter: '{delimiter}'")

    # Determine max column count from the sample so pandas doesn't truncate
    lines = sample.split("\n")
    max_cols = max((line.count(delimiter) + 1 for line in lines if line.strip()), default=1)

    return pd.read_csv(
        io.BytesIO(content),
        sep=delimiter,
        encoding=encoding,
        encoding_errors="replace",
        header=None,
        names=range(max_cols),
        dtype=str,
        skipinitialspace=True,
        on_bad_lines="skip",
    )


def _find_header_row_in_df(df: pd.DataFrame) -> tuple[Optional[int], list[str]]:
    """
    Scan the first 10 rows of a DataFrame looking for a header row
    (contains date + description/amount-like column names).
    """
    for i in range(min(10, len(df))):
        row = [str(v).strip() if pd.notna(v) else "" for v in df.iloc[i]]
        if is_table_header(row):
            return i, row
    return None, []


def _parse_as_savings(
    df: pd.DataFrame,
    col_map: dict,
    bank: BankType,
) -> ParseResult:
    """Parse DataFrame rows as a savings account statement."""
    statement = SavingsAccountStatementSchema()
    statement.account_holder_name = f"{bank.value} Account"

    min_date: date | None = None
    max_date: date | None = None
    first_balance: Decimal | None = None
    last_balance: Decimal | None = None

    for _, row in df.iterrows():
        vals = [str(v).strip() if pd.notna(v) else "" for v in row]

        date_idx = col_map.get("date")
        txn_date = parse_date(vals[date_idx] if date_idx is not None and date_idx < len(vals) else "")
        if txn_date is None:
            continue

        desc_idx = col_map.get("description")
        description = vals[desc_idx] if desc_idx is not None and desc_idx < len(vals) else ""
        ref_idx = col_map.get("reference")
        reference = vals[ref_idx] if ref_idx is not None and ref_idx < len(vals) else ""

        deb_idx = col_map.get("debit")
        cred_idx = col_map.get("credit")
        bal_idx = col_map.get("balance")

        debit = parse_amount(vals[deb_idx] if deb_idx is not None and deb_idx < len(vals) else "")
        credit = parse_amount(vals[cred_idx] if cred_idx is not None and cred_idx < len(vals) else "")
        balance = parse_amount(vals[bal_idx] if bal_idx is not None and bal_idx < len(vals) else "")

        # If only a single "amount" column exists, determine type from sign
        if debit is None and credit is None and col_map.get("amount") is not None:
            amt_idx = col_map["amount"]
            amount = parse_amount(vals[amt_idx] if amt_idx < len(vals) else "")
            if amount is not None:
                if amount < 0:
                    debit = abs(amount)
                else:
                    credit = amount

        if debit and debit > 0:
            txn_type = TransactionType.DEBIT
        elif credit and credit > 0:
            txn_type = TransactionType.CREDIT
        else:
            continue

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

        if min_date is None or txn_date < min_date:
            min_date = txn_date
        if max_date is None or txn_date > max_date:
            max_date = txn_date
        if balance is not None:
            if first_balance is None:
                first_balance = balance
            last_balance = balance

    if not statement.transactions:
        return ParseResult.failure("No transactions found")

    statement.from_date = min_date
    statement.to_date = max_date
    if first_balance is not None:
        txn0 = statement.transactions[0]
        if txn0.withdrawal_amount:
            statement.opening_balance = first_balance + txn0.withdrawal_amount
        elif txn0.deposit_amount:
            statement.opening_balance = first_balance - txn0.deposit_amount
        else:
            statement.opening_balance = first_balance
    statement.closing_balance = last_balance

    logger.info(f"CSV/Excel savings parse: {len(statement.transactions)} transactions")
    return ParseResult.ok(statement)


def _parse_as_credit_card(
    df: pd.DataFrame,
    col_map: dict,
    bank: BankType,
) -> ParseResult:
    """Parse DataFrame rows as a credit card statement."""
    statement = CreditCardStatementSchema()
    statement.card_holder_name = f"{bank.value} Card"

    min_date: date | None = None
    max_date: date | None = None

    for _, row in df.iterrows():
        vals = [str(v).strip() if pd.notna(v) else "" for v in row]

        date_idx = col_map.get("date")
        txn_date = parse_date(vals[date_idx] if date_idx is not None and date_idx < len(vals) else "")
        if txn_date is None:
            continue

        desc_idx = col_map.get("description")
        description = vals[desc_idx] if desc_idx is not None and desc_idx < len(vals) else ""
        ref_idx = col_map.get("reference")
        reference = vals[ref_idx] if ref_idx is not None and ref_idx < len(vals) else ""

        deb_idx = col_map.get("debit")
        cred_idx = col_map.get("credit")

        debit = parse_amount(vals[deb_idx] if deb_idx is not None and deb_idx < len(vals) else "")
        credit = parse_amount(vals[cred_idx] if cred_idx is not None and cred_idx < len(vals) else "")

        # Single amount column
        if debit is None and credit is None and col_map.get("amount") is not None:
            amt_idx = col_map["amount"]
            amount = parse_amount(vals[amt_idx] if amt_idx < len(vals) else "")
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
        return ParseResult.failure("No transactions found")

    statement.statement_date = max_date

    logger.info(f"CSV/Excel credit card parse: {len(statement.transactions)} transactions")
    return ParseResult.ok(statement)
