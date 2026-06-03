from datetime import date
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models.bank_account import BankAccount
from app.models.enums import SourceType, TransactionType, ReviewStatus
from app.models.transaction import UnifiedTransaction
from app.schemas.transaction import UnifiedTransactionSchema
from app.services.transaction_service import UnifiedTransactionService


def _make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return session_factory()


class TestUnifiedTransactionService:
    def test_query_filters_by_bank_account_id(self):
        db = _make_session()
        try:
            bob = BankAccount(
                name="BOB Savings",
                bank_name="BOB",
                account_type="SAVINGS",
                account_number=None,
                holder_name="Bob",
            )
            hdfc = BankAccount(
                name="HDFC Savings",
                bank_name="HDFC",
                account_type="SAVINGS",
                account_number=None,
                holder_name="Hdfc",
            )
            db.add_all([bob, hdfc])
            db.flush()

            db.add_all(
                [
                    UnifiedTransaction(
                        date=date(2026, 5, 1),
                        description="SAVINGS ACCOUNT",
                        amount=Decimal("1.00"),
                        type=TransactionType.DEBIT,
                        source_type=SourceType.SAVINGS,
                        bank="BOB",
                        bank_account_id=bob.id,
                    ),
                    UnifiedTransaction(
                        date=date(2025, 2, 28),
                        description="NEFT Salary",
                        amount=Decimal("67723.00"),
                        type=TransactionType.CREDIT,
                        source_type=SourceType.SAVINGS,
                        bank="HDFC",
                        bank_account_id=hdfc.id,
                    ),
                ]
            )
            db.commit()

            results = UnifiedTransactionService.query(
                db,
                bank_account_id=hdfc.id,
                source_type=SourceType.SAVINGS,
                limit=20,
            )

            assert len(results) == 1
            assert results[0].description == "NEFT Salary"
            assert results[0].bank_account_id == hdfc.id
        finally:
            db.close()

    def test_query_filters_by_review_status_and_schema_exposes_it(self):
        db = _make_session()
        try:
            db.add_all(
                [
                    UnifiedTransaction(
                        date=date(2026, 5, 1),
                        description="Needs review import",
                        amount=Decimal("1.00"),
                        type=TransactionType.DEBIT,
                        source_type=SourceType.SAVINGS,
                        bank="BOB",
                        review_status=ReviewStatus.NEEDS_REVIEW.value,
                    ),
                    UnifiedTransaction(
                        date=date(2026, 5, 2),
                        description="Trusted import",
                        amount=Decimal("2.00"),
                        type=TransactionType.CREDIT,
                        source_type=SourceType.SAVINGS,
                        bank="HDFC",
                        review_status=ReviewStatus.AUTO_PARSED.value,
                    ),
                ]
            )
            db.commit()

            results = UnifiedTransactionService.query(
                db,
                review_status=ReviewStatus.NEEDS_REVIEW,
                limit=20,
            )

            assert len(results) == 1
            assert results[0].description == "Needs review import"

            payload = UnifiedTransactionSchema.model_validate(results[0]).model_dump(mode="json")
            assert payload["review_status"] == ReviewStatus.NEEDS_REVIEW.value
        finally:
            db.close()