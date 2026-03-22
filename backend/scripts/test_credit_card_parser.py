"""
Test script for the generic PDF statement parser.
Tests parsing against any bank statement PDF.
"""
import sys
import argparse
import logging
from pathlib import Path
from decimal import Decimal

# Add parent dir to path
sys.path.insert(0, str(Path(__file__).parent))

from app.parsers.generic_pdf_parser import GenericPdfParser
from app.models.enums import StatementType


def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(levelname)-5s | %(name)s | %(message)s",
    )


def test_regex_parser(pdf_path: str, verbose: bool = False):
    """Test generic PDF parsing."""
    parser = GenericPdfParser()
    stmt_type = StatementType.SAVINGS

    print(f"\n{'='*60}")
    print(f"  GENERIC PDF PARSER TEST")
    print(f"  PDF: {pdf_path}")
    print(f"  Type: {stmt_type.value}")
    print(f"{'='*60}\n")

    result = parser.parse(pdf_path, stmt_type)

    if not result.success:
        print(f"❌ PARSE FAILED: {result.error_message}")
        return False

    stmt = result.result
    print("Parse succeeded!\n")

    # Print metadata
    print("-- Metadata --")
    if hasattr(stmt, 'account_holder_name'):
        print(f"  Account Holder: {stmt.account_holder_name}")
        print(f"  From Date:      {stmt.from_date}")
        print(f"  To Date:        {stmt.to_date}")
        print(f"  Opening Bal:    {stmt.opening_balance}")
        print(f"  Closing Bal:    {stmt.closing_balance}")
    elif hasattr(stmt, 'card_holder_name'):
        print(f"  Card Holder:    {stmt.card_holder_name}")
        print(f"  Statement Date: {stmt.statement_date}")

    # Print transactions
    print(f"\n-- Transactions ({len(stmt.transactions)}) --")
    total_debit = Decimal("0")
    total_credit = Decimal("0")
    for i, txn in enumerate(stmt.transactions, 1):
        txn_type = txn.type.value if txn.type else "?"
        if hasattr(txn, 'withdrawal_amount'):
            amt = txn.withdrawal_amount or txn.deposit_amount or Decimal("0")
        else:
            amt = txn.amount or Decimal("0")
        if txn_type == "CREDIT":
            total_credit += amt
        else:
            total_debit += amt
        desc = (txn.description or "")[:50]
        print(f"  {i:2d}. {txn_type:6s} {txn.date} | {desc:<50} | {str(amt):>12}")

    print(f"\n-- Summary --")
    print(f"  Total Debits:  {total_debit}")
    print(f"  Total Credits: {total_credit}")

    if len(stmt.transactions) < 1:
        print("\n  WARNING: No transactions found!")
        return False

    print(f"\n  Parsing succeeded with {len(stmt.transactions)} transactions!")
    return True


def test_llm_parser(pdf_path: str, verbose: bool = False):
    """Test LLM-based parsing."""
    parser = GenericPdfParser()

    print(f"\n{'='*60}")
    print(f"  LLM PARSER TEST")
    print(f"  PDF: {pdf_path}")
    print(f"{'='*60}\n")

    raw_text = parser.extract_raw_text(pdf_path)
    print(f"Extracted {len(raw_text)} chars of text")

    from app.parsers.llm_parser import parse_with_llm_generic
    from app.models.enums import BankType
    result = parse_with_llm_generic(raw_text, BankType.OTHER, StatementType.CREDIT_CARD)

    if not result.success:
        print(f"❌ LLM PARSE FAILED: {result.error_message}")
        return False

    stmt = result.result
    print(f"✅ LLM parse succeeded: {len(stmt.transactions)} transactions\n")

    for i, txn in enumerate(stmt.transactions, 1):
        type_icon = "🟢" if txn.type.value == "CREDIT" else "🔴"
        amt = txn.amount or Decimal("0")
        desc = (txn.description or "")[:50]
        print(f"  {i:2d}. {type_icon} {txn.date} | {desc:<50} | {str(amt):>12}")

    return True


if __name__ == "__main__":
    argparser = argparse.ArgumentParser(description="Test generic PDF parser")
    argparser.add_argument(
        "--pdf",
        default=str(Path(__file__).parent.parent / "credit-card-statement.pdf"),
        help="Path to the PDF file",
    )
    argparser.add_argument(
        "--mode",
        choices=["regex", "llm", "both"],
        default="regex",
        help="Parser mode to test",
    )
    argparser.add_argument("-v", "--verbose", action="store_true")
    args = argparser.parse_args()

    setup_logging(args.verbose)

    if args.mode in ("regex", "both"):
        test_regex_parser(args.pdf, args.verbose)

    if args.mode in ("llm", "both"):
        test_llm_parser(args.pdf, args.verbose)
