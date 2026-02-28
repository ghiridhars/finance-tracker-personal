"""
HDFC Savings Account PDF Parser.
Replaces: HdfcSavingsPdfParser.java (133 lines)

All regex patterns ported 1:1 from Java. Notes on each pattern inline.

Migration notes:
  - Java Pattern.compile → Python re.compile
  - Java BigDecimal → Python Decimal
  - Java LocalDate → Python datetime.date
  - Java DateTimeFormatter → Python datetime.strptime
  - Reference number heuristic ported exactly (exclusion list: BLOCK|REV|CWDR)
  - Opening balance calculation ported exactly
"""
import logging
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from app.parsers.base_parser import BaseStatementParser, ParseResult
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)

logger = logging.getLogger(__name__)


class HdfcSavingsPdfParser(BaseStatementParser):
    """
    Parser for HDFC Savings Account PDF statements.
    Replaces: HdfcSavingsPdfParser.java
    """

    # ──────────────────────────────────────────────────────────────
    # Regex patterns — ported 1:1 from Java
    # ──────────────────────────────────────────────────────────────

    # Statement period: "Statement From : dd/MM/yyyy To : dd/MM/yyyy"
    # Java: Statement\s+From\s*:\s*(\d{2}/\d{2}/\d{4})\s*To\s*:\s*(\d{2}/\d{2}/\d{4})
    STATEMENT_DATE_PATTERN = re.compile(
        r"Statement\s+From\s*:\s*(\d{2}/\d{2}/\d{4})\s*To\s*:\s*(\d{2}/\d{2}/\d{4})"
    )

    # 14-digit account number
    # Java: Account\s+No\s*:\s*(\d{14})
    ACCOUNT_INFO_PATTERN = re.compile(r"Account\s+No\s*:\s*(\d{14})")

    # Customer name: line before "Customer ID"
    # Java: (?m)^\s*([^\n]+)\s*\n\s*Customer\s+ID
    CUSTOMER_NAME_PATTERN = re.compile(r"(?m)^\s*([^\n]+)\s*\n\s*Customer\s+ID")

    # IFSC code: 4 letters + 0 + 6 alphanumeric
    # Java: IFSC\s+Code\s*:\s*([A-Z]{4}0[A-Z0-9]{6})
    IFSC_PATTERN = re.compile(r"IFSC\s+Code\s*:\s*([A-Z]{4}0[A-Z0-9]{6})")

    # Transaction line: Date | Desc | ValueDate | Debit | Credit | Balance
    # dd/MM/yy format for dates, amounts with commas
    # Java: (\d{2}/\d{2}/\d{2})\s+([^\n]+?)\s+(\d{2}/\d{2}/\d{2})\s+([0-9,]+\.\d{2})\s+([0-9,]+\.\d{2})\s+([0-9,]+\.\d{2})
    TRANSACTION_PATTERN = re.compile(
        r"(\d{2}/\d{2}/\d{2})\s+([^\n]+?)\s+(\d{2}/\d{2}/\d{2})\s+([0-9,]+\.\d{2})\s+([0-9,]+\.\d{2})\s+([0-9,]+\.\d{2})"
    )

    # Branch name
    # Java: Branch\s*:\s*([^\n]+)
    BRANCH_NAME_PATTERN = re.compile(r"Branch\s*:\s*([^\n]+)")

    # Reference number exclusion list (heuristic)
    REF_EXCLUSION_PATTERN = re.compile(r"(?i)^(BLOCK|REV|CWDR)$")

    def parse_text(self, text: str) -> ParseResult:
        """
        Parse extracted text into a SavingsAccountStatementSchema.
        Replaces: HdfcSavingsPdfParser.parseText(String)
        """
        if not text or not text.strip():
            return ParseResult.failure("Empty text")

        try:
            statement = SavingsAccountStatementSchema()

            self._extract_metadata(text, statement)
            self._extract_transactions(text, statement)

            if not statement.transactions:
                return ParseResult.failure("No transactions found")

            return ParseResult.ok(statement)

        except Exception as e:
            logger.error(f"Parsing Error: {e}", exc_info=True)
            return ParseResult.failure(f"Parsing Error: {e}")

    def _extract_metadata(self, text: str, statement: SavingsAccountStatementSchema) -> None:
        """
        Extract statement metadata.
        Replaces: HdfcSavingsPdfParser.extractMetadata(String, SavingsAccountStatementDto)
        """
        # Account Number
        m = self.ACCOUNT_INFO_PATTERN.search(text)
        if m:
            statement.account_number = m.group(1)

        # Statement Period (from/to dates)
        m = self.STATEMENT_DATE_PATTERN.search(text)
        if m:
            statement.from_date = self._parse_date_long(m.group(1))
            statement.to_date = self._parse_date_long(m.group(2))

        # IFSC
        m = self.IFSC_PATTERN.search(text)
        if m:
            statement.ifsc_code = m.group(1)

        # Branch
        m = self.BRANCH_NAME_PATTERN.search(text)
        if m:
            statement.branch_name = m.group(1).strip()

        # Customer Name (line before "Customer ID")
        m = self.CUSTOMER_NAME_PATTERN.search(text)
        if m:
            statement.account_holder_name = m.group(1).strip()

    def _extract_transactions(self, text: str, statement: SavingsAccountStatementSchema) -> None:
        """
        Extract transaction lines using regex.
        Replaces: HdfcSavingsPdfParser.extractTransactions(String, SavingsAccountStatementDto)
        """
        for match in self.TRANSACTION_PATTERN.finditer(text):
            try:
                txn = SavingsAccountTransactionSchema()

                # Date (dd/MM/yy short format)
                date_str = match.group(1)
                txn.date = self._parse_date_short(date_str)

                # Description and Reference Number handling
                raw_desc = match.group(2).strip()
                description = raw_desc
                ref_no = ""

                # Heuristic: last token with digits is likely a reference number
                # Excluding common words: BLOCK, REV, CWDR
                last_space_idx = raw_desc.rfind(" ")
                if last_space_idx != -1:
                    last_token = raw_desc[last_space_idx + 1:]
                    # Check if last token contains digits and is not in exclusion list
                    if (
                        re.search(r"\d", last_token)
                        and not self.REF_EXCLUSION_PATTERN.match(last_token)
                    ):
                        ref_no = last_token
                        description = raw_desc[:last_space_idx].strip()

                txn.description = description
                txn.reference_number = ref_no

                # Debit / Credit / Balance
                debit = self._parse_money(match.group(4))
                credit = self._parse_money(match.group(5))
                balance = self._parse_money(match.group(6))

                txn.withdrawal_amount = debit
                txn.deposit_amount = credit
                txn.closing_balance = balance

                # Set type based on withdrawal vs deposit
                txn.type = "DEBIT" if debit > 0 else "CREDIT"

                statement.transactions.append(txn)

                # Update statement closing balance to latest line
                statement.closing_balance = balance

            except Exception as e:
                logger.warning(f"Skipping malformed line: {match.group()} — {e}")

        # Refine opening balance if transactions exist
        # Formula: opening = first_tx.closing + first_tx.withdrawal - first_tx.deposit
        if statement.transactions:
            first = statement.transactions[0]
            opening = (
                (first.closing_balance or Decimal("0"))
                + (first.withdrawal_amount or Decimal("0"))
                - (first.deposit_amount or Decimal("0"))
            )
            statement.opening_balance = opening

    @staticmethod
    def _parse_date_long(date_str: str) -> date:
        """Parse dd/MM/yyyy date string."""
        return datetime.strptime(date_str, "%d/%m/%Y").date()

    @staticmethod
    def _parse_date_short(date_str: str) -> date:
        """Parse dd/MM/yy date string."""
        return datetime.strptime(date_str, "%d/%m/%y").date()

    @staticmethod
    def _parse_money(amount: str) -> Decimal:
        """Parse money string, stripping commas."""
        if not amount:
            return Decimal("0")
        try:
            return Decimal(amount.replace(",", ""))
        except InvalidOperation:
            return Decimal("0")
