"""
LLM-based parser for bank statements.

Uses an LLM (Google Gemini or Ollama) to extract structured data from
raw PDF text when the regex-based parser fails or encounters an unknown format.

Supports any bank's savings or credit card statement via parse_with_llm_generic().
"""
import json
import logging
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from app.config import settings
from app.models.enums import BankType, StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import SavingsAccountStatementSchema, SavingsAccountTransactionSchema

logger = logging.getLogger(__name__)

# System prompt for LLM extraction
EXTRACTION_PROMPT = """You are a financial document parser. Extract ALL data from this HDFC credit card statement text into structured JSON.

Rules:
1. Extract ALL transactions — every line with a date and amount is a transaction.
2. Dates must be in "YYYY-MM-DD" format.
3. Amounts must be plain numbers (no currency symbols, no commas). Example: 16114.65
4. Transaction type: "DEBIT" for purchases/charges, "CREDIT" for payments/refunds/cashbacks.
   - Lines marked with "+" or containing "PAYMENT", "CASHBACK", "REFUND" are CREDIT.
   - All other transactions are DEBIT.
5. Extract the reference number from "(Ref# XXXXX)" if present.
6. For the statement metadata, extract: statement_date, due_date, card_number, card_holder_name,
   credit_limit, total_dues, minimum_amount_due.

Return ONLY valid JSON matching this schema:
{
  "statement_date": "YYYY-MM-DD",
  "due_date": "YYYY-MM-DD",
  "card_number": "string",
  "card_holder_name": "string",
  "credit_limit": number,
  "total_dues": number,
  "minimum_amount_due": number,
  "transactions": [
    {
      "date": "YYYY-MM-DD",
      "description": "string",
      "amount": number,
      "type": "DEBIT" or "CREDIT",
      "reference_number": "string or null"
    }
  ]
}
"""

def _json_to_statement(data: dict) -> CreditCardStatementSchema:
    """Convert raw LLM JSON output to a CreditCardStatementSchema."""
    statement = CreditCardStatementSchema()

    # Metadata
    if data.get("statement_date"):
        statement.statement_date = _parse_date(data["statement_date"])
    if data.get("due_date"):
        statement.due_date = _parse_date(data["due_date"])
    statement.card_number = data.get("card_number")
    statement.card_holder_name = data.get("card_holder_name")

    if data.get("credit_limit") is not None:
        statement.credit_limit = Decimal(str(data["credit_limit"]))
    if data.get("total_dues") is not None:
        statement.total_dues = Decimal(str(data["total_dues"]))
    if data.get("minimum_amount_due") is not None:
        statement.minimum_amount_due = Decimal(str(data["minimum_amount_due"]))

    # Transactions
    for txn_data in data.get("transactions", []):
        txn = CreditCardTransactionSchema()
        if txn_data.get("date"):
            txn.date = _parse_date(txn_data["date"])
        txn.description = txn_data.get("description")
        if txn_data.get("amount") is not None:
            txn.amount = Decimal(str(txn_data["amount"]))
        txn_type = txn_data.get("type", "DEBIT").upper()
        txn.type = TransactionType.CREDIT if txn_type == "CREDIT" else TransactionType.DEBIT
        txn.reference_number = txn_data.get("reference_number")
        statement.transactions.append(txn)

    return statement


def _parse_date(date_str: str) -> Optional[date]:
    """Parse ISO date string from LLM output."""
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str.strip(), "%Y-%m-%d").date()
    except ValueError:
        logger.warning(f"LLM returned unparseable date: {date_str}")
        return None


# ═══════════════════════════════════════════════════════════════
# Generic bank-agnostic LLM parser (new)
# ═══════════════════════════════════════════════════════════════

SAVINGS_EXTRACTION_PROMPT = """You are a financial document parser. Extract ALL data from this bank savings/current account statement into structured JSON.

Rules:
1. Extract ALL transactions — every line with a date and amount is a transaction.
2. Dates must be in "YYYY-MM-DD" format.
3. Amounts must be plain numbers (no currency symbols, no commas). Example: 16114.65
4. Transaction type: "DEBIT" for withdrawals, "CREDIT" for deposits.
5. Extract the reference number if present.
6. Extract account metadata: account_number, account_holder_name, ifsc_code, branch_name,
   from_date (statement start), to_date (statement end), opening_balance, closing_balance.
7. For each transaction, extract: withdrawal_amount (if debit), deposit_amount (if credit), closing_balance (running balance after transaction).

Return ONLY valid JSON matching this schema:
{
  "account_number": "string",
  "account_holder_name": "string",
  "ifsc_code": "string or null",
  "branch_name": "string or null",
  "from_date": "YYYY-MM-DD",
  "to_date": "YYYY-MM-DD",
  "opening_balance": number,
  "closing_balance": number,
  "transactions": [
    {
      "date": "YYYY-MM-DD",
      "description": "string",
      "reference_number": "string or null",
      "withdrawal_amount": number_or_null,
      "deposit_amount": number_or_null,
      "closing_balance": number,
      "type": "DEBIT" or "CREDIT"
    }
  ]
}
"""

GENERIC_CREDIT_CARD_PROMPT = """You are a financial document parser. Extract ALL data from this credit card statement into structured JSON.

This may be from ANY bank (HDFC, ICICI, SBI, Axis, Kotak, or others). Identify the bank and adapt accordingly.

Rules:
1. Extract ALL transactions — every line with a date and amount is a transaction.
2. Dates must be in "YYYY-MM-DD" format.
3. Amounts must be plain numbers (no currency symbols, no commas). Example: 16114.65
4. Transaction type: "DEBIT" for purchases/charges, "CREDIT" for payments/refunds/cashbacks.
5. Extract the reference number if present.
6. For the statement metadata, extract: statement_date, due_date, card_number (masked is fine),
   card_holder_name, credit_limit, total_dues, minimum_amount_due.

Return ONLY valid JSON matching this schema:
{
  "statement_date": "YYYY-MM-DD",
  "due_date": "YYYY-MM-DD",
  "card_number": "string",
  "card_holder_name": "string",
  "credit_limit": number,
  "total_dues": number,
  "minimum_amount_due": number,
  "transactions": [
    {
      "date": "YYYY-MM-DD",
      "description": "string",
      "amount": number,
      "type": "DEBIT" or "CREDIT",
      "reference_number": "string or null"
    }
  ]
}
"""


def parse_with_llm_generic(
    text: str,
    bank: BankType,
    statement_type: StatementType,
) -> ParseResult:
    """
    Generic bank-agnostic LLM parser.
    Works for any bank's savings or credit card statement.
    """
    provider = settings.llm_provider.lower()

    if provider == "none":
        return ParseResult.failure("LLM parsing disabled (LLM_PROVIDER=none)")

    # Choose the right prompt
    if statement_type == StatementType.CREDIT_CARD:
        prompt = GENERIC_CREDIT_CARD_PROMPT
    elif statement_type in (StatementType.SAVINGS, StatementType.CURRENT):
        prompt = SAVINGS_EXTRACTION_PROMPT
    else:
        return ParseResult.failure(f"Unsupported statement type for LLM: {statement_type}")

    # Add bank context to help the LLM
    bank_hint = f"\nThis statement is from {bank.value} bank.\n" if bank != BankType.OTHER else ""

    full_prompt = f"{prompt}{bank_hint}"

    logger.info(f"Generic LLM parsing: {bank.value}/{statement_type.value} with {provider}")

    try:
        if provider == "gemini":
            raw_json = _call_llm_gemini(full_prompt, text)
        elif provider == "ollama":
            raw_json = _call_llm_ollama(full_prompt, text)
        else:
            return ParseResult.failure(f"Unknown LLM provider: {provider}")

        # Convert to appropriate schema
        if statement_type == StatementType.CREDIT_CARD:
            result = _json_to_statement(raw_json)
        else:
            result = _json_to_savings_statement(raw_json)

        txn_count = len(result.transactions)
        logger.info(f"Generic LLM parse succeeded: {txn_count} transactions")
        return ParseResult.ok(result)

    except ImportError as e:
        logger.warning(f"LLM provider library not installed: {e}")
        return ParseResult.failure(
            f"LLM provider '{provider}' library not installed. "
            f"Install with: pip install {'google-genai' if provider == 'gemini' else 'ollama'}"
        )
    except Exception as e:
        logger.error(f"Generic LLM parsing failed: {e}", exc_info=True)
        return ParseResult.failure(f"LLM parsing failed: {e}")


def _call_llm_gemini(system_prompt: str, text: str) -> dict:
    """Call Gemini with a given system prompt and text."""
    from google import genai

    if not settings.gemini_api_key:
        raise ValueError("GEMINI_API_KEY not set.")

    client = genai.Client(api_key=settings.gemini_api_key)
    response = client.models.generate_content(
        model=settings.gemini_model,
        contents=f"{system_prompt}\n\n--- STATEMENT TEXT ---\n{text}",
        config=genai.types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.0,
        ),
    )
    return json.loads(response.text)


def _call_llm_ollama(system_prompt: str, text: str) -> dict:
    """Call Ollama with a given system prompt and text."""
    import ollama

    client = ollama.Client(host=settings.ollama_host)
    response = client.chat(
        model=settings.ollama_model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text},
        ],
        format="json",
        options={"temperature": 0.0},
    )
    return json.loads(response.message.content)


def _json_to_savings_statement(data: dict) -> SavingsAccountStatementSchema:
    """Convert LLM JSON output to a SavingsAccountStatementSchema."""
    statement = SavingsAccountStatementSchema()

    statement.account_number = data.get("account_number")
    statement.account_holder_name = data.get("account_holder_name")
    statement.ifsc_code = data.get("ifsc_code")
    statement.branch_name = data.get("branch_name")

    if data.get("from_date"):
        statement.from_date = _parse_date(data["from_date"])
    if data.get("to_date"):
        statement.to_date = _parse_date(data["to_date"])
    if data.get("opening_balance") is not None:
        statement.opening_balance = Decimal(str(data["opening_balance"]))
    if data.get("closing_balance") is not None:
        statement.closing_balance = Decimal(str(data["closing_balance"]))

    for txn_data in data.get("transactions", []):
        txn = SavingsAccountTransactionSchema()
        if txn_data.get("date"):
            txn.date = _parse_date(txn_data["date"])
        txn.description = txn_data.get("description")
        txn.reference_number = txn_data.get("reference_number")

        if txn_data.get("withdrawal_amount") is not None:
            txn.withdrawal_amount = Decimal(str(txn_data["withdrawal_amount"]))
        if txn_data.get("deposit_amount") is not None:
            txn.deposit_amount = Decimal(str(txn_data["deposit_amount"]))
        if txn_data.get("closing_balance") is not None:
            txn.closing_balance = Decimal(str(txn_data["closing_balance"]))

        txn_type = txn_data.get("type", "DEBIT").upper()
        txn.type = TransactionType.CREDIT if txn_type == "CREDIT" else TransactionType.DEBIT

        statement.transactions.append(txn)

    return statement
