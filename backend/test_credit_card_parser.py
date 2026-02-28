"""
Test script for the HDFC Credit Card parser.
Tests both regex and LLM parsing against the real statement PDF.
"""
import sys
import argparse
import logging
from pathlib import Path
from decimal import Decimal

# Add parent dir to path
sys.path.insert(0, str(Path(__file__).parent))

from app.parsers.hdfc_credit_card_parser import HdfcCreditCardPdfParser
from app.schemas.credit_card import CreditCardStatementSchema


def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(levelname)-5s | %(name)s | %(message)s",
    )


def test_regex_parser(pdf_path: str, verbose: bool = False):
    """Test regex-based parsing."""
    parser = HdfcCreditCardPdfParser()

    print(f"\n{'='*60}")
    print(f"  REGEX PARSER TEST")
    print(f"  PDF: {pdf_path}")
    print(f"{'='*60}\n")

    result = parser.parse(pdf_path)

    if not result.success:
        print(f"❌ PARSE FAILED: {result.error_message}")
        return False

    stmt: CreditCardStatementSchema = result.result
    print("✅ Parse succeeded!\n")

    # Print metadata
    print("── Metadata ──")
    print(f"  Card Holder:    {stmt.card_holder_name}")
    print(f"  Card Number:    {stmt.card_number}")
    print(f"  Statement Date: {stmt.statement_date}")
    print(f"  Due Date:       {stmt.due_date}")
    print(f"  Credit Limit:   {stmt.credit_limit}")
    print(f"  Available:      {stmt.available_credit}")
    print(f"  Total Dues:     {stmt.total_dues}")
    print(f"  Minimum Due:    {stmt.minimum_amount_due}")

    # Print transactions
    print(f"\n── Transactions ({len(stmt.transactions)}) ──")
    total_debit = Decimal("0")
    total_credit = Decimal("0")
    for i, txn in enumerate(stmt.transactions, 1):
        type_icon = "🟢" if txn.type.value == "CREDIT" else "🔴"
        amt = txn.amount or Decimal("0")
        if txn.type.value == "CREDIT":
            total_credit += amt
        else:
            total_debit += amt
        desc = (txn.description or "")[:50]
        print(f"  {i:2d}. {type_icon} {txn.date} | {desc:<50} | {str(amt):>12}")

    print(f"\n── Summary ──")
    print(f"  Total Debits:  {total_debit}")
    print(f"  Total Credits: {total_credit}")
    print(f"  Net:           {total_debit - total_credit}")

    # Validate expected values for the known test PDF
    errors = []

    if stmt.statement_date:
        if str(stmt.statement_date) != "2026-02-17":
            errors.append(f"Statement date: expected 2026-02-17, got {stmt.statement_date}")
    else:
        errors.append("Statement date: missing")

    if stmt.card_number:
        if "4279" not in stmt.card_number:
            errors.append(f"Card number: expected ...4279, got {stmt.card_number}")
    else:
        errors.append("Card number: missing")

    if stmt.due_date:
        if str(stmt.due_date) != "2026-03-09":
            errors.append(f"Due date: expected 2026-03-09, got {stmt.due_date}")
    else:
        errors.append("Due date: missing")

    if stmt.minimum_amount_due:
        if stmt.minimum_amount_due != Decimal("1360.00"):
            errors.append(f"Min due: expected 1360.00, got {stmt.minimum_amount_due}")
    else:
        errors.append("Minimum due: missing")

    if len(stmt.transactions) < 10:
        errors.append(f"Too few transactions: expected >= 10, got {len(stmt.transactions)}")

    if errors:
        print(f"\n⚠️  Validation Issues ({len(errors)}):")
        for e in errors:
            print(f"  - {e}")
    else:
        print(f"\n✅ All validations passed!")

    return len(errors) == 0


def test_llm_parser(pdf_path: str, verbose: bool = False):
    """Test LLM-based parsing."""
    parser = HdfcCreditCardPdfParser()

    print(f"\n{'='*60}")
    print(f"  LLM PARSER TEST")
    print(f"  PDF: {pdf_path}")
    print(f"{'='*60}\n")

    # Extract text first
    raw_text = parser.extract_raw_text(pdf_path)
    print(f"Extracted {len(raw_text)} chars of text")

    from app.parsers.llm_parser import parse_with_llm
    result = parse_with_llm(raw_text)

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
    argparser = argparse.ArgumentParser(description="Test HDFC CC parser")
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
