"""
Generic bank-agnostic PDF statement parser.

Uses three extraction strategies (tried in order):
  1. Table extraction (pdfplumber extract_tables) — works for banks with clean
     table formatting (e.g., Federal Bank, HDFC).
  2. Single-line text parsing — for PDFs where each transaction is one line
     with date + description + amounts.
  3. Multi-line text parsing — for PDFs where each column value is on a
     separate line (e.g., Bank of Baroda). Reassembles vertical blocks
     of serial/date/description/debit/credit/balance into transactions.

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

from app.config import settings
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

    Tries three strategies in order:
      1. Table extraction (pdfplumber)
      2. Single-line text parsing
      3. Multi-line text parsing
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

            # Strategy 2 & 3: text-based parsing (pymupdf — faster text)
            raw_text = self.extract_raw_text(file_path)

            if settings.debug:
                try:
                    _dbg = Path(file_path).parent / "last_parsed_text.txt"
                    _dbg.write_text(raw_text, encoding="utf-8")
                    logger.debug(f"Dumped extracted text to {_dbg}")
                except Exception:
                    pass

            result = self._try_text_strategy(raw_text, statement_type)
            if result and result.success:
                logger.info("Single-line text strategy succeeded")
                return result

            # Strategy 3a/3b: credit-card-specific multi-line strategies
            # (run before generic multi-line to avoid false positives)
            if statement_type == StatementType.CREDIT_CARD:
                # date|time + desc + amount
                result = self._try_cc_multiline_strategy(raw_text)
                if result and result.success:
                    logger.info("Credit card multi-line strategy succeeded")
                    return result

                # date / desc / amount [Cr]
                result = self._try_cc_simple_multiline_strategy(raw_text)
                if result and result.success:
                    logger.info("Credit card simple multi-line strategy succeeded")
                    return result

            # Strategy 4: generic multi-line text parsing
            result = self._try_multiline_strategy(raw_text, statement_type)
            if result and result.success:
                logger.info("Multi-line text strategy succeeded")
                return result

            return ParseResult.failure(
                "Could not extract transactions from PDF using "
                "table, single-line text, or multi-line text strategy."
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

    # ── Strategy 3: Multi-line text parsing ───────────────────

    # Patterns for multi-line detection
    _ML_DATE_RE = re.compile(r"^\d{2}[/-]\d{2}[/-]\d{2,4}$")
    _ML_SERIAL_RE = re.compile(r"^\d{1,4}$")
    _ML_AMOUNT_RE = re.compile(r"^[\d,]+(?:\.\d{1,2})?$")
    _ML_DASH_RE = re.compile(r"^-$")

    def _try_multiline_strategy(
        self, text: str, statement_type: StatementType
    ) -> ParseResult | None:
        """
        Parse PDFs where each table column is on its own line.

        Expected repeating block pattern:
            serial_no       (1-4 digit number)
            txn_date        (dd-mm-yyyy)
            value_date      (dd-mm-yyyy, optional)
            description     (1+ non-amount lines)
            debit           (amount or "-")
            credit          (amount or "-")
            balance         (amount)

        Works for Bank of Baroda and similar layouts.
        """
        lines = [l.strip() for l in text.split("\n")]

        # Quick check: does this look like a multi-line format?
        # Count standalone date lines (not part of larger text)
        date_lines = sum(1 for l in lines if self._ML_DATE_RE.match(l))
        if date_lines < 4:  # need at least a few date-only lines
            return None

        transactions: list[dict] = []
        opening_balance: Decimal | None = None
        i = 0

        while i < len(lines):
            line = lines[i]

            if not line or _NOISE.search(line):
                i += 1
                continue

            # Detect opening balance
            if line.lower() == "opening balance":
                for j in range(i + 1, min(i + 4, len(lines))):
                    val = lines[j].strip()
                    if self._ML_DASH_RE.match(val):
                        continue
                    amt = parse_amount(val)
                    if amt is not None:
                        opening_balance = amt
                        i = j + 1
                        break
                else:
                    i += 1
                continue

            # Try to parse a transaction block
            txn = self._try_parse_multiline_block(lines, i)
            if txn:
                transactions.append(txn["data"])
                i = txn["next_index"]
            else:
                i += 1

        if not transactions:
            return None

        return self._build_result(transactions, statement_type, opening_balance)

    def _try_parse_multiline_block(self, lines: list[str], start: int) -> dict | None:
        """
        Try to parse a transaction block starting at index `start`.

        Returns {"data": {transaction dict}, "next_index": int} or None.
        """
        i = start
        n = len(lines)
        if i >= n:
            return None

        line = lines[i]

        # Step 1: Optional serial number
        if self._ML_SERIAL_RE.match(line):
            i += 1
            if i >= n:
                return None

        # Step 2: Transaction date (required)
        if i >= n or not self._ML_DATE_RE.match(lines[i]):
            return None
        txn_date = parse_date(lines[i])
        if txn_date is None:
            return None
        i += 1

        # Step 3: Optional value date
        if i < n and self._ML_DATE_RE.match(lines[i]):
            i += 1

        # Step 4: Description (1+ lines until we hit amount/dash/serial+date)
        desc_lines: list[str] = []
        while i < n:
            l = lines[i]
            if self._ML_AMOUNT_RE.match(l) or self._ML_DASH_RE.match(l):
                break
            if self._ML_SERIAL_RE.match(l) and i + 1 < n and self._ML_DATE_RE.match(lines[i + 1]):
                break
            if _NOISE.search(l):
                break
            if not l:
                break
            desc_lines.append(l)
            i += 1

        description = " ".join(desc_lines).strip()

        # Step 5: Debit (amount or "-")
        if i >= n:
            return None
        debit = self._parse_amount_or_dash(lines[i])
        i += 1

        # Step 6: Credit (amount or "-")
        if i >= n:
            return None
        credit = self._parse_amount_or_dash(lines[i])
        i += 1

        # Step 7: Balance (required amount)
        if i >= n:
            return None
        balance = parse_amount(lines[i])
        if balance is None:
            return None
        i += 1

        # Must have at least one of debit/credit
        if debit is None and credit is None:
            return None

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
            "next_index": i,
        }

    @staticmethod
    def _parse_amount_or_dash(text: str) -> Decimal | None:
        """Parse amount, treating '-' as None."""
        text = text.strip()
        if text == "-":
            return None
        return parse_amount(text)

    # ── Strategy 4: Credit card multi-line parsing ──────────

    # Date with pipe+time: "18/01/2026| 14:34" or "18/01/2026 | 14:34"
    # Also matches "18/01/2026 14:34:56" (space-separated time, no pipe)
    _CC_DATE_TIME_RE = re.compile(
        r"^(\d{2}[/-]\d{2}[/-]\d{2,4})\s*(?:\||\s)\s*\d{2}:\d{2}"
    )
    # Amount line: optional "+" then currency symbol/letter then amount
    # e.g., " C 245.00", "+  C 26,317.00", "+ \u20b9 245.00"
    _CC_AMOUNT_RE = re.compile(
        r"^(\+)?\s*[C\u20b9$]\s*([\d,]+\.\d{2})$"
    )

    def _try_cc_multiline_strategy(self, text: str) -> ParseResult | None:
        """
        Parse credit card PDFs where transactions span multiple lines.

        Pattern (e.g., HDFC RuPay):
            DD/MM/YYYY| HH:MM           \u2190 date line
            [EMI]                        \u2190 optional prefix
            description [(Ref# xxx)]    \u2190 description
            [+]  C amount               \u2190 amount (+ = credit/payment)
            l                            \u2190 category indicator (skip)
        """
        lines = [l.strip() for l in text.split("\n")]

        # Quick check: do we have date|time lines?
        date_time_count = sum(1 for l in lines if self._CC_DATE_TIME_RE.match(l))
        if date_time_count < 2:
            return None

        transactions: list[dict] = []
        i = 0

        while i < len(lines):
            line = lines[i]

            # Look for date|time line
            m = self._CC_DATE_TIME_RE.match(line)
            if not m:
                i += 1
                continue

            txn_date = parse_date(m.group(1))
            if txn_date is None:
                i += 1
                continue
            i += 1

            # Collect description lines until we hit an amount line
            desc_lines: list[str] = []
            is_credit = False
            amount: Decimal | None = None
            ref: str | None = None

            while i < len(lines):
                l = lines[i]

                # Check if this is the amount line
                am = self._CC_AMOUNT_RE.match(l)
                if am:
                    is_credit = am.group(1) == "+"
                    amount = parse_amount(am.group(2))
                    i += 1
                    # Skip trailing category indicator (single char like "l")
                    if i < len(lines) and len(lines[i].strip()) <= 2:
                        i += 1
                    break

                # Check if we hit the next date (no amount found — skip)
                if self._CC_DATE_TIME_RE.match(l):
                    break

                # Skip noise
                if _NOISE.search(l):
                    i += 1
                    continue

                # Extract reference number if present
                ref_m = re.search(r"\(Ref#\s*([^)]+)\)", l)
                if ref_m:
                    ref = ref_m.group(1).strip()

                if l and l != "l":  # skip standalone category markers
                    desc_lines.append(l)
                i += 1

            if amount is None or amount <= 0:
                continue

            description = " ".join(desc_lines).strip()
            # Clean up "EMI" prefix that appears on a separate line before desc
            if description.startswith("EMI "):
                description = description[4:].strip()

            txn_type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT

            transactions.append({
                "date": txn_date,
                "description": description or None,
                "reference": ref,
                "debit": amount if not is_credit else None,
                "credit": amount if is_credit else None,
                "balance": None,
                "type": txn_type,
            })

        if not transactions:
            return None

        return self._build_credit_card_result(transactions)

    # ── Strategy 5: Simple credit card multi-line parsing ───

    # Standalone date line (with optional time component)
    _CC_SIMPLE_DATE_RE = re.compile(r"^(\d{2}[/-]\d{2}[/-]\d{2,4})(?:\s+\d{2}:\d{2}(?::\d{2})?)?$")
    # Amount with optional Cr suffix: "948.00", "8,779.00 Cr"
    _CC_SIMPLE_AMOUNT_RE = re.compile(
        r"^([\d,]+\.\d{2})\s*(?:(Cr|CR|cr))?\s*$"
    )

    def _try_cc_simple_multiline_strategy(self, text: str) -> ParseResult | None:
        """
        Parse credit card PDFs with simple multi-line format:
            DD/MM/YYYY          ← date line
            DESCRIPTION         ← 1+ description lines
            AMOUNT [Cr]         ← amount, with optional Cr suffix for credits

        Common in HDFC Bank credit card statements.
        """
        lines = [l.strip() for l in text.split("\n")]

        # Quick check: need enough standalone date lines
        date_line_count = sum(1 for l in lines if self._CC_SIMPLE_DATE_RE.match(l))
        if date_line_count < 3:
            return None

        transactions: list[dict] = []
        i = 0

        while i < len(lines):
            line = lines[i]

            # Look for a standalone date line
            dm = self._CC_SIMPLE_DATE_RE.match(line)
            if not dm:
                i += 1
                continue

            # Skip if this date is followed by known non-transaction context
            # (e.g., "Opening Balance", "Closing Balance" on the next line)
            txn_date = parse_date(dm.group(1))
            if txn_date is None:
                i += 1
                continue
            i += 1

            # Collect description lines until we hit an amount line or next date
            desc_lines: list[str] = []
            is_credit = False
            amount: Decimal | None = None
            ref: str | None = None

            while i < len(lines):
                l = lines[i]

                # Skip blank lines within a transaction block
                if not l:
                    i += 1
                    continue

                # Check if this is an amount line
                am = self._CC_SIMPLE_AMOUNT_RE.match(l)
                if am:
                    amount = parse_amount(am.group(1))
                    is_credit = am.group(2) is not None
                    i += 1
                    break

                # Check if we hit the next date line (no amount found — stop)
                if self._CC_SIMPLE_DATE_RE.match(l):
                    break

                # Check if we hit a section boundary
                if _NOISE.search(l):
                    i += 1
                    continue

                # Skip known non-transaction sections
                lower = l.lower()
                if any(kw in lower for kw in (
                    "reward points", "opening balance", "closing balance",
                    "cash points", "important information", "total dues",
                    "payment due", "credit limit",
                )):
                    # This date was a header date, not a transaction
                    amount = None
                    break

                # Extract reference number if present
                ref_m = re.search(r"\(Ref#\s*([^)]+)\)", l)
                if ref_m:
                    ref = ref_m.group(1).strip()

                desc_lines.append(l)
                i += 1

            if amount is None or amount <= 0:
                continue

            description = " ".join(desc_lines).strip()
            if not description:
                continue

            txn_type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT

            transactions.append({
                "date": txn_date,
                "description": description or None,
                "reference": ref,
                "debit": amount if not is_credit else None,
                "credit": amount if is_credit else None,
                "balance": None,
                "type": txn_type,
            })

        if not transactions:
            return None

        return self._build_credit_card_result(transactions)

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

        # Account number patterns (savings)
        acct_patterns = [
            r"account\s*(?:number|no\.?)[:\s]*(\d[\d\s]{5,}\d)",
            r"a/c\s*(?:number|no\.?)[:\s]*(\d[\d\s]{5,}\d)",
            r"account\s*(?:number|no\.?)[:\s]*(\w+)",
        ]
        for pat in acct_patterns:
            acct = re.search(pat, text, re.IGNORECASE)
            if acct:
                meta["account_number"] = acct.group(1).strip()
                break

        # Credit card number — masked patterns like 4632 02XX XXXX 4418
        card_patterns = [
            r"card\s*(?:number|no\.?)[:\s]*([\dXx*]{4}[\s-]?[\dXx*]{4}[\s-]?[\dXx*]{4}[\s-]?[\dXx*]{4})",
            r"(\d{4,6}[Xx*]{4,6}\d{4})",  # contiguous masked: 463202XXXXXX4418
        ]
        for pat in card_patterns:
            card = re.search(pat, text, re.IGNORECASE)
            if card:
                meta["card_number"] = card.group(1).strip()
                break

        return meta
