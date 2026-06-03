import logging
from datetime import date
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsers.base_parser import ParseResult
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)

logger = logging.getLogger(__name__)


def build_result(
    transactions: list[dict],
    statement_type: StatementType,
    opening_balance: Decimal | None = None,
) -> ParseResult:
    if not transactions:
        return ParseResult.failure("No transactions found in PDF")

    if statement_type == StatementType.CREDIT_CARD:
        return build_credit_card_result(transactions)

    return build_savings_result(transactions, opening_balance)


def build_savings_result(
    transactions: list[dict],
    opening_balance: Decimal | None = None,
) -> ParseResult:
    statement = SavingsAccountStatementSchema()

    min_date: date | None = None
    max_date: date | None = None
    first_balance: Decimal | None = None
    last_balance: Decimal | None = None

    for transaction in transactions:
        txn = SavingsAccountTransactionSchema(
            date=transaction["date"],
            description=transaction.get("description"),
            reference_number=transaction.get("reference"),
            withdrawal_amount=transaction.get("debit"),
            deposit_amount=transaction.get("credit"),
            closing_balance=transaction.get("balance"),
            type=transaction.get("type"),
        )
        statement.transactions.append(txn)

        txn_date = transaction["date"]
        if min_date is None or txn_date < min_date:
            min_date = txn_date
        if max_date is None or txn_date > max_date:
            max_date = txn_date
        if transaction.get("balance") is not None:
            if first_balance is None:
                first_balance = transaction["balance"]
            last_balance = transaction["balance"]

    statement.from_date = min_date
    statement.to_date = max_date
    statement.closing_balance = last_balance

    if opening_balance is not None:
        statement.opening_balance = opening_balance
    elif first_balance is not None:
        first_transaction = transactions[0]
        if first_transaction.get("debit") and first_transaction["debit"] > 0:
            statement.opening_balance = first_balance + first_transaction["debit"]
        elif first_transaction.get("credit") and first_transaction["credit"] > 0:
            statement.opening_balance = first_balance - first_transaction["credit"]
        else:
            statement.opening_balance = first_balance

    logger.info("Generic PDF savings parse: %s transactions", len(statement.transactions))
    return ParseResult.ok(statement)


def build_credit_card_result(transactions: list[dict]) -> ParseResult:
    statement = CreditCardStatementSchema()

    max_date: date | None = None

    for transaction in transactions:
        amount = transaction.get("debit") or transaction.get("credit")
        txn_type = transaction.get("type", TransactionType.DEBIT)

        txn = CreditCardTransactionSchema(
            date=transaction["date"],
            description=transaction.get("description"),
            amount=amount,
            type=txn_type,
            reference_number=transaction.get("reference"),
        )
        statement.transactions.append(txn)

        txn_date = transaction["date"]
        if max_date is None or txn_date > max_date:
            max_date = txn_date

    statement.statement_date = max_date

    logger.info("Generic PDF credit card parse: %s transactions", len(statement.transactions))
    return ParseResult.ok(statement)