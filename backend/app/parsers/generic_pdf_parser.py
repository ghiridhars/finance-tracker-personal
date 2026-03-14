"""
Generic bank-agnostic PDF statement parser.

Uses two extraction strategies:
  1. Table extraction (pdfplumber extract_tables) — works for banks with clean
     table formatting (e.g., Federal Bank).
  2. Text-based line parsing — fallback for PDFs where table detection merges
     columns (e.g., Bank of Baroda). Uses date/amount detection to parse
     transaction lines.

Supports any bank's savings or credit card statement PDF.

Uses pymupdf (fitz) for fast text extraction and pdfplumber for table extraction.
"""
import logging
import re
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Optional

import fitz  # pymupdf — fast text extraction
import pdfplumber  # table extraction

from app.models.enums import StatementType, TransactionType
from app.parsers.base_parser import ParseException, ParseResult
from app.parsers.patterns import (
    DATE_PATTERNS,
    VALUE_DATE_PATTERNS,
    DESCRIPTION_PATTERNS,
    DEBIT_PATTERNS,
    CREDIT_PATTERNS,
    AMOUNT_PATTERNS,
    BALANCE_PATTERNS,
    REFERENCE_PATTERNS,
    NOISE_PATTERN as _NOISE,
    LEADING_DATE_RE as _LEADING_DATE,
    DECIMAL_AMOUNT_RE as _DECIMAL_AMOUNT,
    INTEGER_AMOUNT_RE as _INTEGER_AMOUNT,
    parse_date,
    parse_amount,
    map_columns,
    is_table_header,
    get_cell,
)
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)

logger = logging.getLogger(__name__)


class GenericPdfParser:
    """
    Bank-agnostic PDF statement parser.

    Tries table extraction first (pdfplumber for tables),
    then falls back to text-based line parsing (pymupdf for speed).
    """

    def parse(self, file_path: str | Path, statement_type: StatementType) -> ParseResult:
        file_path = Path(file_path)
        if not file_path.exists():
            raise ParseException(f"File not found: {file_path}")

        try:
            # Strategy 1: table extraction (pdfplumber — better for tables)
            with pdfplumber.open(str(file_path)) as pdf:
                if not pdf.pages:
                    return ParseResult.failure("PDF has no pages")

                result = self._try_table_strategy(pdf, statement_type)
                if result and result.success:
                    logger.info("Table extraction strategy succeeded")
                    return result

            # Strategy 2: text-based line parsing (pymupdf — faster text)
            raw_text = self.extract_raw_text(file_path)
            result = self._try_text_strategy(raw_text, statement_type)
            if result and result.success:
                logger.info("Text extraction strategy succeeded")
                return result

            return ParseResult.failure(
                "Could not extract transactions from PDF using either "
                "table or text strategy."
            )
        except ParseException:
            raise
        except Exception as e:
            raise ParseException(f"Failed to parse PDF: {e}", cause=e)

    def extract_raw_text(self, file_path: str | Path) -> str:
        """Extract text using pymupdf (fitz) — significantly faster than pdfplumber."""
        try:
            doc = fitz.open(str(file_path))
            text = "\n".join(page.get_text() for page in doc)
            doc.close()
            return text
        except Exception:
            # Fallback to pdfplumber if pymupdf fails
            with pdfplumber.open(str(file_path)) as pdf:
                return "\n".join(page.extract_text() or "" for page in pdf.pages)

    # ── Strategy 1: Table extraction ──────────────────────────

    def _try_table_strategy(
        self, pdf: pdfplumber.PDF, statement_type: StatementType
    ) -> ParseResult | None:
        col_map: dict | None = None
        all_data_rows: list[list[str]] = []

        for page in pdf.pages:
            for table in page.extract_tables():
                if not table or len(table) < 2:
                    continue

                for i, row in enumerate(table):
                    if self._is_table_header(row):
                        new_map = self._map_table_columns(row)
                        # Accept if we have at least date + one amount column
                        if new_map.get("date") is not None and (
                            new_map.get("debit") is not None
                            or new_map.get("credit") is not None
                            or new_map.get("amount") is not None
                        ):
                            if col_map is None:
                                col_map = new_map
                            # Data rows follow the header
                            all_data_rows.extend(table[i + 1:])
                            break
                else:
                    # No header in this table — continuation from previous page
                    if col_map is not None:
                        all_data_rows.extend(table)

        if col_map is None or not all_data_rows:
            return None

        logger.info(f"Table strategy: col_map={col_map}, {len(all_data_rows)} data rows")
        transactions = self._parse_table_rows(all_data_rows, col_map, statement_type)

        if not transactions:
            return None

        return self._build_result(transactions, statement_type)

    def _is_table_header(self, row: list[str | None]) -> bool:
        return is_table_header(row)

    def _map_table_columns(self, header_row: list[str | None]) -> dict[str, int | None]:
        return map_columns(
            [(c or "") for c in header_row],
            include_value_date=True,
        )

    def _parse_table_rows(
        self,
        rows: list[list[str | None]],
        col_map: dict,
        statement_type: StatementType,
    ) -> list[dict]:
        transactions: list[dict] = []

        for row in rows:
            if not row or all(not (c or "").strip() for c in row):
                continue

            date_val = get_cell(row, col_map["date"])
            # Clean newlines from multi-line cells
            date_val = date_val.replace("\n", " ").strip() if date_val else ""
            txn_date = parse_date(date_val)
            if txn_date is None:
                continue  # skip non-transaction rows (subtotals, blanks, etc.)

            desc = get_cell(row, col_map["description"])
            desc = desc.replace("\n", " ").strip() if desc else ""

            ref = get_cell(row, col_map["reference"])
            ref = ref.replace("\n", " ").strip() if ref else None

            debit = parse_amount(get_cell(row, col_map["debit"]))
            credit = parse_amount(get_cell(row, col_map["credit"]))
            balance = parse_amount(get_cell(row, col_map["balance"]))

            # Single "amount" column — determine sign
            if debit is None and credit is None and col_map["amount"] is not None:
                amt = parse_amount(get_cell(row, col_map["amount"]))
                if amt is not None:
                    if amt < 0:
                        debit = abs(amt)
                    else:
                        credit = amt

            if debit is None and credit is None:
                continue

            txn_type = TransactionType.DEBIT if (debit and debit > 0) else TransactionType.CREDIT

            transactions.append({
                "date": txn_date,
                "description": desc or None,
                "reference": ref,
                "debit": debit,
                "credit": credit,
                "balance": balance,
                "type": txn_type,
            })

        return transactions

    # ── Strategy 2: Text-based line parsing ───────────────────

    def _try_text_strategy(
        self, text: str, statement_type: StatementType
    ) -> ParseResult | None:
        lines = text.split("\n")
        raw_txns: list[dict] = []
        current: dict | None = None
        opening_balance: Decimal | None = None

        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            if _NOISE.search(stripped):
                continue

            # Check for opening balance line
            ob = self._try_opening_balance(stripped)
            if ob is not None:
                opening_balance = ob
                continue

            # Try to parse as a transaction line
            txn = self._parse_txn_line(stripped, statement_type)
            if txn:
                if current:
                    raw_txns.append(current)
                current = txn
            elif current:
                # Continuation line — append to description
                # Avoid appending page footers or repeated headers
                if not _NOISE.search(stripped):
                    prev = current.get("description") or ""
                    current["description"] = (prev + " " + stripped).strip()

        if current:
            raw_txns.append(current)

        if not raw_txns:
            return None

        # Clean up descriptions
        for t in raw_txns:
            if t.get("description"):
                t["description"] = re.sub(r"\s+", " ", t["description"]).strip()

        result = self._build_result(raw_txns, statement_type, opening_balance)
        return result

    def _try_opening_balance(self, line: str) -> Optional[Decimal]:
        """Detect 'Opening Balance' lines and extract the balance value."""
        if "opening balance" not in line.lower():
            return None
        m = re.search(r"([\d,]+(?:\.\d{2})?)\s*(?:CR|DR)?\s*$", line, re.IGNORECASE)
        if m:
            return parse_amount(m.group(1))
        return None

    def _parse_txn_line(self, line: str, statement_type: StatementType) -> dict | None:
        """
        Try to parse a line as a transaction.
        Looks for:
          [serial_no] date [date2] description amount_tokens
        """
        # Remove trailing CR/DR indicator
        clean = re.sub(r"\s+(?:CR|DR)\s*$", "", line, flags=re.IGNORECASE).strip()

        # Find leading date
        m = _LEADING_DATE.match(clean)
        if not m:
            return None

        date_str = m.group(1)
        txn_date = parse_date(date_str)
        if txn_date is None:
            return None

        remaining = clean[m.end():].strip()

        # Skip optional second date (value date)
        m2 = re.match(r"(\d{2}[/-]\d{2}[/-]\d{2,4})\s*", remaining)
        if m2:
            remaining = remaining[m2.end():].strip()

        # Extract trailing amount tokens (right-to-left)
        tokens = remaining.split()
        amount_tokens: list[str] = []
        found_decimal = False
        desc_end_idx = len(tokens)
        max_amounts = 3

        for i in range(len(tokens) - 1, -1, -1):
            if len(amount_tokens) >= max_amounts:
                break
            t = tokens[i]
            if _DECIMAL_AMOUNT.match(t):
                amount_tokens.insert(0, t)
                found_decimal = True
                desc_end_idx = i
            elif t == "-":
                amount_tokens.insert(0, "-")
                desc_end_idx = i
            elif (
                _INTEGER_AMOUNT.match(t)
                and len(t) <= 8  # reasonable amount length
                and int(t.replace(",", "")) < 100_000_000
            ):
                amount_tokens.insert(0, t)
                desc_end_idx = i
            else:
                break

        # Validate: need at least some amounts
        min_amounts = 2 if statement_type == StatementType.SAVINGS else 1
        if len(amount_tokens) < min_amounts:
            return None
        # If no decimals found, require at least 3 tokens to be confident
        if not found_decimal and len(amount_tokens) < 3:
            return None

        description = " ".join(tokens[:desc_end_idx])

        # Classify amounts → debit, credit, balance
        debit, credit, balance = self._classify_amounts(amount_tokens)

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

    def _classify_amounts(
        self, tokens: list[str]
    ) -> tuple[Optional[Decimal], Optional[Decimal], Optional[Decimal]]:
        """
        Given 1–3 amount tokens from right-to-left extraction, determine
        debit, credit, and balance.

        3 tokens: [debit_or_zero, credit_or_zero, balance]
        2 tokens: [amount, balance]
        1 token:  [amount]
        """
        if len(tokens) >= 3:
            d = parse_amount(tokens[-3])
            c = parse_amount(tokens[-2])
            b = parse_amount(tokens[-1])
            debit = d if d and d > 0 else None
            credit = c if c and c > 0 else None
            return debit, credit, b
        elif len(tokens) == 2:
            amt = parse_amount(tokens[0])
            balance = parse_amount(tokens[1])
            # Can't reliably determine type from 2 values alone;
            # default to debit — caller can correct via balance analysis
            return amt, None, balance
        elif len(tokens) == 1:
            amt = parse_amount(tokens[0])
            return amt, None, None
        return None, None, None

    # ── Result building ────────────────────────────────────────

    def _build_result(
        self,
        transactions: list[dict],
        statement_type: StatementType,
        opening_balance: Decimal | None = None,
    ) -> ParseResult:
        if not transactions:
            return ParseResult.failure("No transactions found in PDF")

        if statement_type == StatementType.CREDIT_CARD:
            return self._build_credit_card_result(transactions)
        else:
            return self._build_savings_result(transactions, opening_balance)

    def _build_savings_result(
        self, transactions: list[dict], opening_balance: Decimal | None = None
    ) -> ParseResult:
        statement = SavingsAccountStatementSchema()

        min_date: date | None = None
        max_date: date | None = None
        first_balance: Decimal | None = None
        last_balance: Decimal | None = None

        for t in transactions:
            txn = SavingsAccountTransactionSchema(
                date=t["date"],
                description=t.get("description"),
                reference_number=t.get("reference"),
                withdrawal_amount=t.get("debit"),
                deposit_amount=t.get("credit"),
                closing_balance=t.get("balance"),
                type=t.get("type"),
            )
            statement.transactions.append(txn)

            d = t["date"]
            if min_date is None or d < min_date:
                min_date = d
            if max_date is None or d > max_date:
                max_date = d
            if t.get("balance") is not None:
                if first_balance is None:
                    first_balance = t["balance"]
                last_balance = t["balance"]

        statement.from_date = min_date
        statement.to_date = max_date
        statement.closing_balance = last_balance

        if opening_balance is not None:
            statement.opening_balance = opening_balance
        elif first_balance is not None:
            # Infer opening balance from first transaction
            txn0 = transactions[0]
            if txn0.get("debit") and txn0["debit"] > 0:
                statement.opening_balance = first_balance + txn0["debit"]
            elif txn0.get("credit") and txn0["credit"] > 0:
                statement.opening_balance = first_balance - txn0["credit"]
            else:
                statement.opening_balance = first_balance

        logger.info(f"Generic PDF savings parse: {len(statement.transactions)} transactions")
        return ParseResult.ok(statement)

    def _build_credit_card_result(self, transactions: list[dict]) -> ParseResult:
        statement = CreditCardStatementSchema()

        min_date: date | None = None
        max_date: date | None = None

        for t in transactions:
            amount = t.get("debit") or t.get("credit")
            txn_type = t.get("type", TransactionType.DEBIT)

            txn = CreditCardTransactionSchema(
                date=t["date"],
                description=t.get("description"),
                amount=amount,
                type=txn_type,
                reference_number=t.get("reference"),
            )
            statement.transactions.append(txn)

            d = t["date"]
            if min_date is None or d < min_date:
                min_date = d
            if max_date is None or d > max_date:
                max_date = d

        statement.statement_date = max_date

        logger.info(f"Generic PDF credit card parse: {len(statement.transactions)} transactions")
        return ParseResult.ok(statement)

    # ── Statement metadata extraction ──────────────────────────

    @staticmethod
    def extract_metadata(text: str) -> dict:
        """Extract common metadata from raw PDF text (best-effort)."""
        meta: dict = {}

        # Statement period: "from dd-mm-yyyy to dd-mm-yyyy" or "Period: dd/mm/yyyy to dd/mm/yyyy"
        period = re.search(
            r"(?:from|period[:\s]+)\s*(\d{2}[/-]\d{2}[/-]\d{2,4})\s+to\s+(\d{2}[/-]\d{2}[/-]\d{2,4})",
            text,
            re.IGNORECASE,
        )
        if period:
            meta["period_from"] = period.group(1)
            meta["period_to"] = period.group(2)

        # Account number patterns
        acct = re.search(r"account\s*(?:number|no)[:\s]*(\w+)", text, re.IGNORECASE)
        if acct:
            meta["account_number"] = acct.group(1)

        return meta
