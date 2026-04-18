"""
Credit Card Statement service.
Replaces: app.personal.service.CreditCardStatementService (Java @Service)

Handles persistence, deduplication, and querying of credit card statements.
Uses SQLAlchemy sessions instead of Spring @Transactional + JPA repositories.
"""
import logging
from datetime import date

from sqlalchemy.orm import Session

from app.models.credit_card import CreditCardStatement, CreditCardTransaction
from app.models.enums import TransactionType
from app.schemas.credit_card import CreditCardStatementSchema
from app.services.transaction_service import UnifiedTransactionService

logger = logging.getLogger(__name__)


class CreditCardStatementService:
    """
    Replaces: CreditCardStatementService.java

    Key differences from Java version:
    - Uses SQLAlchemy Session instead of Spring @Autowired Repository
    - @Transactional → SQLAlchemy session.commit() / session.rollback()
    - Stream filter for dedup → SQLAlchemy query filter
    """

    @staticmethod
    def save_statement(
        db: Session,
        dto: CreditCardStatementSchema,
        bank: str | None = None,
        review_status: str | None = None,
        bank_account_id: int | None = None,
    ) -> CreditCardStatement:
        """
        Save or update a credit card statement.
        Replaces: CreditCardStatementService.saveStatement(CreditCardStatementDto)

        Deduplication logic (ported from Java):
          1. Find existing statement by card_number + statement_date
          2. If found → update in place (clear transactions, re-add)
          3. If not found → insert new

        After saving, creates unified transactions for the dashboard.
        """
        # Check for existing statement (replaces Java stream filter)
        existing = (
            db.query(CreditCardStatement)
            .filter(
                CreditCardStatement.card_number == dto.card_number,
                CreditCardStatement.statement_date == dto.statement_date,
            )
            .first()
        )

        if existing:
            logger.info(f"Updating existing statement for card {dto.card_number}, date {dto.statement_date}")
            _map_dto_to_statement(dto, existing)
            if bank_account_id is not None:
                existing.bank_account_id = bank_account_id
            db.commit()
            db.refresh(existing)
            # Create unified transactions
            UnifiedTransactionService.create_from_credit_card(db, existing, bank=bank, review_status=review_status or "AUTO_PARSED", bank_account_id=bank_account_id)
            return existing

        # New statement
        statement = CreditCardStatement()
        _map_dto_to_statement(dto, statement)
        if bank_account_id is not None:
            statement.bank_account_id = bank_account_id
        db.add(statement)
        db.commit()
        db.refresh(statement)
        logger.info(f"Saved new statement id={statement.id} for card {dto.card_number}")

        # Create unified transactions
        UnifiedTransactionService.create_from_credit_card(db, statement, bank=bank, review_status=review_status or "AUTO_PARSED", bank_account_id=bank_account_id)
        return statement

    @staticmethod
    def get_statements_by_card_number(db: Session, card_number: str) -> list[CreditCardStatement]:
        """
        Replaces: CreditCardStatementService.getStatementsByCardNumber(String)
        Replaces: CreditCardStatementRepository.findByCardNumber(String)
        """
        return (
            db.query(CreditCardStatement)
            .filter(CreditCardStatement.card_number == card_number)
            .all()
        )

    @staticmethod
    def get_statements_by_date_range(
        db: Session, start_date: date | None, end_date: date | None
    ) -> list[CreditCardStatement]:
        """
        Replaces: CreditCardStatementService.getStatementsByDateRange(LocalDate, LocalDate)
        Replaces: CreditCardStatementRepository.findByStatementDateBetween(LocalDate, LocalDate)
        """
        query = db.query(CreditCardStatement)
        if start_date is not None:
            query = query.filter(CreditCardStatement.statement_date >= start_date)
        if end_date is not None:
            query = query.filter(CreditCardStatement.statement_date <= end_date)
        return query.all()

    @staticmethod
    def get_transactions_by_date_range(
        db: Session, start_date: date | None, end_date: date | None
    ) -> list[CreditCardTransaction]:
        """
        Replaces: CreditCardStatementService.getTransactionsByDateRange(LocalDate, LocalDate)
        Replaces: CreditCardTransactionRepository.findByDateBetween(LocalDate, LocalDate)
        """
        query = db.query(CreditCardTransaction)
        if start_date is not None:
            query = query.filter(CreditCardTransaction.date >= start_date)
        if end_date is not None:
            query = query.filter(CreditCardTransaction.date <= end_date)
        return query.all()


def _map_dto_to_statement(
    dto: CreditCardStatementSchema, statement: CreditCardStatement
) -> None:
    """
    Map Pydantic schema to SQLAlchemy model.
    Replaces: CreditCardStatementService.mapDtoToStatement(CreditCardStatementDto, CreditCardStatement)
    """
    statement.statement_date = dto.statement_date
    statement.due_date = dto.due_date
    statement.card_number = dto.card_number
    statement.card_holder_name = dto.card_holder_name
    statement.credit_limit = dto.credit_limit
    statement.available_credit = dto.available_credit
    statement.total_dues = dto.total_dues
    statement.minimum_amount_due = dto.minimum_amount_due

    # Clear existing transactions (replaces statement.getTransactions().clear() + orphanRemoval)
    statement.transactions.clear()

    # Add new transactions
    for tx_dto in dto.transactions:
        transaction = CreditCardTransaction()
        transaction.date = tx_dto.date
        transaction.description = tx_dto.description
        transaction.amount = tx_dto.amount
        transaction.type = tx_dto.type
        transaction.reference_number = tx_dto.reference_number
        statement.transactions.append(transaction)
