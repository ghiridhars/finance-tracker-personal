"""
HDFC Credit Card PDF Parser.
Replaces: HdfcCreditCardPdfParser.java (281 lines)

Supports TWO statement formats:
  1. Legacy format (pre-2025): "Card No:", dates as dd/MM/yyyy, "Cr" suffix for credits
  2. UPI RuPay format (2025+): "Credit Card No.", dates as dd Mon, yyyy,
     "C" currency prefix, "+" for credits, date|time format

All regex patterns ported 1:1 from Java for the legacy format.
New patterns added for UPI RuPay format with automatic format detection.

Migration notes:
  - Java Pattern.compile → Python re.compile (same syntax, minor escaping differences)
  - Java Matcher.find() → Python re.search() / re.finditer()
  - Java BigDecimal → Python Decimal
  - Java LocalDate → Python datetime.date
  - Java DateTimeFormatter → Python datetime.strptime
  - FIX: Replaced hardcoded year 2023 fallback with current year
  - FIX: Replaced System.out.println debug with proper logging
"""
import logging
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from app.models.enums import TransactionType
from app.parsers.base_parser import BaseStatementParser, ParseResult
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema

logger = logging.getLogger(__name__)


class HdfcCreditCardPdfParser(BaseStatementParser):
    """
    Parser for HDFC Credit Card PDF statements.
    Replaces: HdfcCreditCardPdfParser.java

    Supports both legacy and UPI RuPay statement formats.
    """

    # ──────────────────────────────────────────────────────────────
    # Format detection
    # ──────────────────────────────────────────────────────────────
    UPI_RUPAY_MARKER = re.compile(
        r"(?:UPI\s+RuPay\s+Credit\s+Card|Credit\s+Card\s+No\.)", re.IGNORECASE
    )

    # ──────────────────────────────────────────────────────────────
    # Legacy regex patterns — ported 1:1 from Java
    # ──────────────────────────────────────────────────────────────

    # Matches transaction lines: date + description + amount (with optional CR/C suffix)
    LEGACY_TRANSACTION_PATTERN = re.compile(
        r"(?m)^\s*(\d{1,2}/\d{1,2}(?:/\d{2,4})?|\d{1,2}/\d{4})\s+([^\n]+?)\s+([0-9,]+\.?\d*\s*(?:[Cc][Rr]|[Cc])?|[0-9,]+\.?\d*)\s*$"
    )

    # Statement Date: dd/MM/yyyy
    LEGACY_STATEMENT_DATE_PATTERN = re.compile(r"Statement\s+Date:?\s*([\d/]+)")

    # Masked card number: 1234 56XX XXXX 7890
    LEGACY_CARD_NUMBER_PATTERN = re.compile(r"Card\s+No:?\s*(\d{4}\s*\d{2}XX\s*XXXX\s*\d{4})")

    # Payment due date
    LEGACY_DUE_DATE_PATTERN = re.compile(
        r"(?:Payment\s+Due\s+Date[^\n]*?|[^\n]*?)(\d{2}/\d{2}/\d{4})(?:[^\n]*?(?:Due|Amount|Rs|\d+[.,]\d{2})[^\n]*)?"
    )

    # Credit limit
    LEGACY_CREDIT_LIMIT_PATTERN = re.compile(r"Credit\s+Limit\s*(\d+,?\d*)")

    # Cardholder name
    LEGACY_CARD_HOLDER_PATTERN = re.compile(r"Name\s*:\s*([^\n]+)")

    # Total dues
    LEGACY_TOTAL_DUES_PATTERN = re.compile(r"Total\s*(\d+,?\d*\.?\d*)")

    # Minimum amount due
    LEGACY_MIN_DUE_PATTERN = re.compile(r"(?:Min|Minimum)\s*(?:Amount\s*)?Due\s*(\d+,?\d*\.?\d*)")

    # ──────────────────────────────────────────────────────────────
    # UPI RuPay format patterns (2025+)
    # ──────────────────────────────────────────────────────────────

    # Card number: "Credit Card No. 653029XXXXXX4279"
    NEW_CARD_NUMBER_PATTERN = re.compile(
        r"Credit\s+Card\s+No\.?\s*(\d+X+\d+)"
    )

    # Statement Date: "Statement Date 17 Feb, 2026"
    NEW_STATEMENT_DATE_PATTERN = re.compile(
        r"Statement\s+Date\s+(\d{1,2}\s+\w{3,},?\s+\d{4})"
    )

    # Billing Period: "Billing Period 18 Jan, 2026 - 17 Feb, 2026"
    NEW_BILLING_PERIOD_PATTERN = re.compile(
        r"Billing\s+Period\s+(\d{1,2}\s+\w{3,},?\s+\d{4})\s*-\s*(\d{1,2}\s+\w{3,},?\s+\d{4})"
    )

    # Due Date + Minimum Due on same line: "C1,360.00 09 Mar, 2026"
    # (appears after "MINIMUM DUE DUE DATE" header)
    NEW_DUE_MIN_LINE_PATTERN = re.compile(
        r"C\s*([\d,]+\.\d{2})\s+(\d{1,2}\s+\w{3,},?\s+\d{4})"
    )

    # Total Amount Due: value near "TOTAL AMOUNT DUE"
    NEW_TOTAL_DUES_PATTERN = re.compile(
        r"_\s*C\s*([\d,]+\.\d{2})"
    )

    # Credit Limit line: "C61,000 C33,990 C0"
    # (total credit, available credit, available cash)
    NEW_CREDIT_LIMITS_PATTERN = re.compile(
        r"C\s*([\d,]+)\s+C\s*([\d,]+)\s+C\s*(\d+)"
    )

    # Cardholder: "GHIRIDHAR S Credit Card No."
    NEW_CARD_HOLDER_PATTERN = re.compile(
        r"^([A-Z][A-Z\s]+?)\s+Credit\s+Card\s+No\.", re.MULTILINE
    )

    # Transaction line: "18/01/2026| 14:34 EMI UPI-MMTCPAMP C 16,114.65 l"
    # Credit line:      "18/01/2026| 14:25 + C 26,317.00 l"
    # With inline desc: "22/01/2026| 00:00 CASHBACK FOR REDEMPTION OF PO220126 + C 1,200.00 l"
    NEW_TRANSACTION_PATTERN = re.compile(
        r"^\s*(\d{2}/\d{2}/\d{4})\|\s*(\d{2}:\d{2})\s+"  # date | time
        r"(.*?)"                                            # description (non-greedy)
        r"\s*(\+)?\s*"                                      # optional credit marker
        r"C\s+([\d,]+\.\d{2})"                              # C amount
        r"\s+l\s*$",                                        # PI indicator
        re.MULTILINE
    )

    # Transaction section markers
    TRANSACTION_SECTION_START = re.compile(r"(?m)^\s*(?:Domestic|International)\s+Transactions?.*$")

    # Legacy end markers
    LEGACY_SECTION_END = re.compile(
        r"important\s+information|cash\s+points|reward\s+points|due\s+date", re.IGNORECASE
    )

    # New end markers (added TRANSACTIONS TOTAL AMOUNT)
    SECTION_END = re.compile(
        r"TRANSACTIONS\s+TOTAL\s+AMOUNT|important\s+information|cash\s+points|reward\s+points",
        re.IGNORECASE,
    )

    # Alternative due date pattern (legacy)
    ALTERNATIVE_DUE_DATE_PATTERN = re.compile(r"(\d{2}/\d{2}/\d{4})\s+[\d,]+\.\d{2}\s+[\d,]+\.\d{2}")
    ALL_DATES_PATTERN = re.compile(r"\d{2}/\d{2}/\d{4}")

    def parse_text(self, text: str) -> ParseResult:
        """
        Parse extracted text into a CreditCardStatementSchema.
        Auto-detects format (legacy vs UPI RuPay) and uses appropriate patterns.
        """
        if not text or not text.strip():
            logger.warning("Received empty or null text")
            return ParseResult.failure("Empty text")

        try:
            logger.info(f"Starting to parse text of length: {len(text)}")
            logger.debug(f"Text preview (first 200 chars):\n{text[:200]}")

            # Detect format
            is_new_format = bool(self.UPI_RUPAY_MARKER.search(text))
            logger.info(f"Detected format: {'UPI RuPay (new)' if is_new_format else 'Legacy'}")

            statement = CreditCardStatementSchema()

            logger.info("Extracting metadata...")
            if is_new_format:
                self._extract_metadata_new(text, statement)
            else:
                self._extract_metadata_legacy(text, statement)

            logger.info("Extracting transactions...")
            if is_new_format:
                self._extract_transactions_new(text, statement)
            else:
                self._extract_transactions_legacy(text, statement)

            logger.info("Validating statement...")
            if not self._validate_statement(statement):
                return ParseResult.failure("Statement validation failed")

            return ParseResult.ok(statement)

        except Exception as e:
            logger.error(f"Exception during parsing: {e}", exc_info=True)
            return ParseResult.failure(f"Failed to parse statement: {e}")

    # ──────────────────────────────────────────────────────────────
    # Metadata extraction — UPI RuPay format
    # ──────────────────────────────────────────────────────────────

    def _extract_metadata_new(self, text: str, statement: CreditCardStatementSchema) -> None:
        """Extract metadata from UPI RuPay format statements."""

        # Card Holder Name (before "Credit Card No.")
        m = self.NEW_CARD_HOLDER_PATTERN.search(text)
        if m:
            statement.card_holder_name = m.group(1).strip()
            logger.debug(f"Found Card Holder: {statement.card_holder_name}")

        # Card Number
        m = self.NEW_CARD_NUMBER_PATTERN.search(text)
        if m:
            statement.card_number = m.group(1).strip()
            logger.debug(f"Found Card Number: {statement.card_number}")

        # Statement Date
        m = self.NEW_STATEMENT_DATE_PATTERN.search(text)
        if m:
            date_str = m.group(1).strip()
            logger.debug(f"Found Statement Date: {date_str}")
            statement.statement_date = self._parse_date_flexible(date_str)

        # Due Date + Minimum Due (on same line after "MINIMUM DUE DUE DATE" header)
        min_due_pos = text.upper().find("MINIMUM DUE")
        if min_due_pos != -1:
            search_area = text[min_due_pos:min_due_pos + 200]
            m = self.NEW_DUE_MIN_LINE_PATTERN.search(search_area)
            if m:
                statement.minimum_amount_due = self._parse_money(m.group(1))
                statement.due_date = self._parse_date_flexible(m.group(2).strip())
                logger.debug(f"Found Minimum Due: {statement.minimum_amount_due}")
                logger.debug(f"Found Due Date: {statement.due_date}")

        # Total Amount Due: look for "_ CXX,XXX.XX" pattern
        m = self.NEW_TOTAL_DUES_PATTERN.search(text)
        if m:
            statement.total_dues = self._parse_money(m.group(1))
            logger.debug(f"Found Total Dues: {statement.total_dues}")
        else:
            # Fallback: look for TOTAL AMOUNT DUE section
            total_pos = text.upper().find("TOTAL AMOUNT DUE")
            if total_pos != -1:
                area = text[total_pos:total_pos + 200]
                amounts = re.findall(r"C\s*([\d,]+\.\d{2})", area)
                if amounts:
                    statement.total_dues = self._parse_money(amounts[0])

        # Credit Limits: "C61,000 C33,990 C0" line
        m = self.NEW_CREDIT_LIMITS_PATTERN.search(text)
        if m:
            statement.credit_limit = self._parse_money(m.group(1))
            statement.available_credit = self._parse_money(m.group(2))
            logger.debug(f"Found Credit Limit: {statement.credit_limit}")
            logger.debug(f"Found Available Credit: {statement.available_credit}")

    # ──────────────────────────────────────────────────────────────
    # Metadata extraction — Legacy format
    # ──────────────────────────────────────────────────────────────

    def _extract_metadata_legacy(self, text: str, statement: CreditCardStatementSchema) -> None:
        """
        Extract statement metadata (dates, card number, limits).
        Replaces: HdfcCreditCardPdfParser.extractMetadata(String, CreditCardStatementDto)
        """
        # Statement Date
        m = self.LEGACY_STATEMENT_DATE_PATTERN.search(text)
        if m:
            date_str = m.group(1).strip()
            logger.debug(f"Found Statement Date: {date_str}")
            statement.statement_date = self._parse_date(date_str)

        # Card Number
        m = self.LEGACY_CARD_NUMBER_PATTERN.search(text)
        if m:
            card_num = re.sub(r"\s+", "", m.group(1))
            logger.debug(f"Found Card Number: {card_num}")
            statement.card_number = card_num

        # Due Date
        all_dates = self.ALL_DATES_PATTERN.findall(text)
        logger.debug(f"All dates found in text: {', '.join(all_dates)}")

        m = self.LEGACY_DUE_DATE_PATTERN.search(text)
        if m:
            due_date_str = m.group(1).strip()
            logger.debug(f"Found Due Date: {due_date_str}")
            try:
                statement.due_date = self._parse_date(due_date_str)
            except Exception as e:
                logger.warning(f"Failed to parse due date '{due_date_str}': {e}")
        else:
            m_alt = self.ALTERNATIVE_DUE_DATE_PATTERN.search(text)
            if m_alt:
                statement.due_date = self._parse_date(m_alt.group(1))

        # Credit Limit
        m = self.LEGACY_CREDIT_LIMIT_PATTERN.search(text)
        if m:
            statement.credit_limit = self._parse_money(m.group(1))

        # Card Holder Name
        m = self.LEGACY_CARD_HOLDER_PATTERN.search(text)
        if m:
            statement.card_holder_name = m.group(1).strip()

        # Total Dues
        m = self.LEGACY_TOTAL_DUES_PATTERN.search(text)
        if m:
            statement.total_dues = self._parse_money(m.group(1))

        # Minimum Due
        m = self.LEGACY_MIN_DUE_PATTERN.search(text)
        if m:
            statement.minimum_amount_due = self._parse_money(m.group(1))

    # ──────────────────────────────────────────────────────────────
    # Transaction extraction — UPI RuPay format
    # ──────────────────────────────────────────────────────────────

    def _extract_transactions_new(self, text: str, statement: CreditCardStatementSchema) -> None:
        """Extract transactions from UPI RuPay format statements.

        The NEW_TRANSACTION_PATTERN is specific enough (date|time + C amount + l PI)
        that it only matches actual transaction lines, so we search the full text
        rather than trying to isolate transaction sections.
        """
        # Continuation line pattern: text between two transaction lines that
        # looks like a description (contains Ref#, PAYMENT, etc.)
        CONTINUATION_PATTERN = re.compile(
            r"(?:Ref#|PAYMENT|UPI|EMI|CASHBACK|IGST|Net\s*Banking)", re.IGNORECASE
        )

        for match in self.NEW_TRANSACTION_PATTERN.finditer(text):
            try:
                txn = CreditCardTransactionSchema()

                # Date
                date_str = match.group(1)
                txn.date = self._parse_date(date_str)

                # Description
                desc = match.group(3).strip()

                # Check for description continuation on the line BEFORE this match
                match_line_start = text.rfind("\n", 0, match.start()) + 1
                if match_line_start > 1:
                    line_before_start = text.rfind("\n", 0, match_line_start - 1) + 1
                    line_before = text[line_before_start:match_line_start - 1].strip()

                    # Only prepend if it looks like a transaction description fragment
                    if (line_before
                        and not re.match(r"\d{2}/\d{2}/\d{4}\|", line_before)
                        and CONTINUATION_PATTERN.search(line_before)):
                        desc = f"{line_before} {desc}".strip() if desc else line_before

                # Credit detection: "+" marker
                is_credit = match.group(4) is not None
                txn.type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT

                # Amount
                txn.amount = self._parse_money(match.group(5))

                # Set description
                txn.description = desc if desc else None

                # Extract Ref# if present in description
                if desc:
                    ref_match = re.search(r"\(Ref#\s*([^)]+)\)", desc)
                    if ref_match:
                        txn.reference_number = ref_match.group(1).strip()

                statement.transactions.append(txn)
                logger.debug(
                    f"Found transaction: {txn.date} | {txn.description} "
                    f"| {txn.amount} | {txn.type}"
                )

            except Exception as e:
                logger.warning(f"Failed to parse transaction: {e}")

        logger.info(f"Extracted {len(statement.transactions)} transactions (new format)")

    # ──────────────────────────────────────────────────────────────
    # Transaction extraction — Legacy format
    # ──────────────────────────────────────────────────────────────

    def _extract_transactions_legacy(self, text: str, statement: CreditCardStatementSchema) -> None:
        """
        Extract transactions from the transaction section (legacy format).
        Replaces: HdfcCreditCardPdfParser.extractTransactions()
        """
        start_match = self.TRANSACTION_SECTION_START.search(text)
        if not start_match:
            logger.debug("Transaction section start marker not found")
            return

        start_pos = start_match.start()
        remaining = text[start_pos:]
        end_match = self.LEGACY_SECTION_END.search(remaining)
        end_pos = start_pos + end_match.start() if end_match else len(text)

        transaction_section = text[start_pos:end_pos]
        logger.info(f"Found transaction section ({end_pos - start_pos} chars)")

        for match in self.LEGACY_TRANSACTION_PATTERN.finditer(transaction_section):
            try:
                txn = CreditCardTransactionSchema()
                orig_date_str = match.group(1)
                date_str = orig_date_str
                parts = date_str.split("/")

                if len(parts) == 2:
                    if len(parts[1]) == 4:
                        date_str = f"01/{parts[0]}/{parts[1]}"
                    else:
                        if statement.statement_date is not None:
                            year = statement.statement_date.year
                            date_str = f"{parts[0]}/{parts[1]}/{year}"
                        else:
                            current_year = datetime.now().year
                            date_str = f"{parts[0]}/{parts[1]}/{current_year}"
                elif len(parts) != 3:
                    raise ValueError(f"Invalid date format: {date_str}")

                txn.date = self._parse_date(date_str)

                desc = match.group(2).strip()
                txn.description = desc

                amount_str = match.group(3).strip()
                is_credit = amount_str.lower().endswith("cr") or amount_str.lower().endswith("c")
                if is_credit:
                    amount_str = re.sub(r"(?i)[cr]+\s*$", "", amount_str).strip()

                txn.amount = self._parse_money(amount_str)
                txn.type = TransactionType.CREDIT if is_credit else TransactionType.DEBIT

                if "Ref#" in desc:
                    ref_start = desc.index("Ref#") + 4
                    ref_end = desc.find(")", ref_start)
                    if ref_end != -1:
                        txn.reference_number = desc[ref_start:ref_end].strip()

                statement.transactions.append(txn)
                logger.debug(
                    f"Found transaction: {txn.date} | {txn.description} "
                    f"| {txn.amount} | {txn.type}"
                )

            except Exception as e:
                logger.warning(f"Failed to parse transaction: {e}")

    # ──────────────────────────────────────────────────────────────
    # Validation
    # ──────────────────────────────────────────────────────────────

    def _validate_statement(self, statement: CreditCardStatementSchema) -> bool:
        """Validate parsed statement."""
        has_statement_date = statement.statement_date is not None
        has_due_date = statement.due_date is not None
        has_card_number = statement.card_number is not None
        has_transactions = len(statement.transactions) > 0

        logger.info("Validation Results:")
        logger.info(f"  Statement Date: {statement.statement_date} [{'✓' if has_statement_date else '✗'}]")
        logger.info(f"  Due Date: {statement.due_date} [{'✓' if has_due_date else '✗'}]")
        logger.info(f"  Card Number: {statement.card_number} [{'✓' if has_card_number else '✗'}]")
        logger.info(f"  Transactions: {len(statement.transactions)} [{'✓' if has_transactions else '✗'}]")

        is_valid = has_transactions

        if is_valid:
            if not has_statement_date:
                logger.warning("Missing statement date")
            if not has_due_date:
                logger.warning("Missing due date")
            if not has_card_number:
                logger.warning("Missing card number")

        return is_valid

    # ──────────────────────────────────────────────────────────────
    # Date parsing utilities
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    def _parse_date(date_str: str) -> date:
        """Parse dd/MM/yyyy date string. Replaces Java DateTimeFormatter."""
        return datetime.strptime(date_str, "%d/%m/%Y").date()

    @staticmethod
    def _parse_date_flexible(date_str: str) -> date:
        """Parse date in multiple formats: dd/MM/yyyy, dd Mon, yyyy, dd Mon yyyy."""
        date_str = date_str.strip()
        for fmt in ("%d/%m/%Y", "%d %b, %Y", "%d %B, %Y", "%d %b %Y", "%d %B %Y"):
            try:
                return datetime.strptime(date_str, fmt).date()
            except ValueError:
                continue
        raise ValueError(f"Cannot parse date: {date_str}")

    @staticmethod
    def _parse_money(amount: str) -> Decimal:
        """Parse money string to Decimal, stripping commas and whitespace."""
        cleaned = re.sub(r"[,\s]", "", amount)
        try:
            return Decimal(cleaned)
        except InvalidOperation:
            return Decimal("0")
