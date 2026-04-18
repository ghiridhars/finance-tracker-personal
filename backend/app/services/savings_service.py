"""
Savings Account Statement service.
Replaces: app.personal.service.SavingsAccountStatementService (Java @Service)

Handles persistence, deduplication, and querying of savings account statements.
"""
import logging
from datetime import date

from sqlalchemy.orm import Session

from app.models.savings_account import SavingsAccountStatement, SavingsAccountTransaction
from app.models.enums import TransactionType
from app.schemas.savings_account import SavingsAccountStatementSchema
from app.services.transaction_service import UnifiedTransactionService

logger = logging.getLogger(__name__)


class SavingsAccountStatementService:
    """
    Replaces: SavingsAccountStatementService.java

    Key differences from Java version:
    - Uses SQLAlchemy Session instead of Spring @Autowired Repository
    - @Transactional → SQLAlchemy session.commit() / session.rollback()
    - Stream filter for dedup → SQLAlchemy query filter
    """

    @staticmethod
    def save_statement(
        db: Session,
        dto: SavingsAccountStatementSchema,
        bank: str | None = None,
        review_status: str | None = None,
        bank_account_id: int | None = None,
    ) -> SavingsAccountStatement:
        """
        Save or update a savings account statement.
        Replaces: SavingsAccountStatementService.saveStatement(SavingsAccountStatementDto)

        Deduplication logic (ported from Java):
          1. Find existing by account_number + from_date + to_date
          2. If found → update in place (clear transactions, re-add)
          3. If not found → insert new

        After saving, creates unified transactions for the dashboard.
        """
        # Check for existing statement
        existing = (
            db.query(SavingsAccountStatement)
            .filter(
                SavingsAccountStatement.account_number == dto.account_number,
                SavingsAccountStatement.from_date == dto.from_date,
                SavingsAccountStatement.to_date == dto.to_date,
            )
            .first()
        )

        if existing:
            logger.info(f"Updating existing statement for account {dto.account_number}")
            _map_dto_to_statement(dto, existing)
            if bank_account_id is not None:
                existing.bank_account_id = bank_account_id
            db.commit()
            db.refresh(existing)
            # Create unified transactions
            UnifiedTransactionService.create_from_savings(db, existing, bank=bank, review_status=review_status or "AUTO_PARSED", bank_account_id=bank_account_id)
            return existing

        # New statement
        statement = SavingsAccountStatement()
        _map_dto_to_statement(dto, statement)
        if bank_account_id is not None:
            statement.bank_account_id = bank_account_id
        db.add(statement)
        db.commit()
        db.refresh(statement)
        logger.info(f"Saved new statement id={statement.id} for account {dto.account_number}")

        # Create unified transactions
        UnifiedTransactionService.create_from_savings(db, statement, bank=bank, review_status=review_status or "AUTO_PARSED", bank_account_id=bank_account_id)
        return statement

    @staticmethod
    def get_transactions(
        db: Session, from_date: date | None, to_date: date | None
    ) -> list[SavingsAccountTransaction]:
        """
        Replaces: SavingsAccountStatementService.getTransactions(LocalDate, LocalDate)
        Replaces: SavingsAccountTransactionRepository.findByDateBetween(LocalDate, LocalDate)
        """
        query = db.query(SavingsAccountTransaction)
        if from_date is not None:
            query = query.filter(SavingsAccountTransaction.date >= from_date)
        if to_date is not None:
            query = query.filter(SavingsAccountTransaction.date <= to_date)
        return query.all()


def _map_dto_to_statement(
    dto: SavingsAccountStatementSchema, statement: SavingsAccountStatement
) -> None:
    """
    Map Pydantic schema to SQLAlchemy model.
    Replaces: SavingsAccountStatementService.mapDtoToStatement(...)
    """
    statement.account_number = dto.account_number
    statement.account_holder_name = dto.account_holder_name
    statement.ifsc_code = dto.ifsc_code
    statement.branch_name = dto.branch_name
    statement.from_date = dto.from_date
    statement.to_date = dto.to_date
    statement.opening_balance = dto.opening_balance
    statement.closing_balance = dto.closing_balance

    # Clear existing transactions (replaces orphanRemoval=true)
    statement.transactions.clear()

    # Add new transactions
    for tx_dto in dto.transactions:
        transaction = SavingsAccountTransaction()
        transaction.date = tx_dto.date
        transaction.description = tx_dto.description
        transaction.reference_number = tx_dto.reference_number
        transaction.withdrawal_amount = tx_dto.withdrawal_amount
        transaction.deposit_amount = tx_dto.deposit_amount
        transaction.closing_balance = tx_dto.closing_balance
        # Compute type from amounts (same as Java DTO.getType())
        if tx_dto.withdrawal_amount and tx_dto.withdrawal_amount > 0:
            transaction.type = TransactionType.DEBIT
        else:
            transaction.type = TransactionType.CREDIT
        statement.transactions.append(transaction)
