from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models.bank_account import BankAccount
from app.services.account_resolution_service import AccountResolutionService


def _make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine, tables=[BankAccount.__table__])
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return session_factory()


class TestAccountResolutionService:
    def test_reuses_existing_account_when_formatting_differs(self):
        db = _make_session()
        try:
            existing = BankAccount(
                name="Hdfc Credit Card ••4418",
                bank_name="HDFC",
                account_type="CREDIT_CARD",
                account_number="4632 02XX XXXX 4418",
                holder_name="Hdfc",
            )
            db.add(existing)
            db.commit()

            resolved = AccountResolutionService.resolve_or_create(
                db,
                bank_name="HDFC",
                account_type="CREDIT_CARD",
                account_number="463202XXXXXX4418",
                holder_name="Hdfc",
            )
            db.commit()

            rows = db.scalars(select(BankAccount).order_by(BankAccount.id)).all()
            assert resolved.id == existing.id
            assert len(rows) == 1
        finally:
            db.close()

    def test_new_accounts_store_canonical_identifier(self):
        db = _make_session()
        try:
            created = AccountResolutionService.resolve_or_create(
                db,
                bank_name="HDFC",
                account_type="CREDIT_CARD",
                account_number="6530 29** **** 4279",
                holder_name="Hdfc",
            )
            db.commit()

            saved = db.scalars(select(BankAccount)).one()
            assert created.id == saved.id
            assert saved.account_number == "653029XXXXXX4279"
        finally:
            db.close()

    def test_word_only_savings_identifier_is_treated_as_missing(self):
        db = _make_session()
        try:
            first = AccountResolutionService.resolve_or_create(
                db,
                bank_name="BOB",
                account_type="SAVINGS",
                account_number="NOMINEE",
                holder_name="Bob",
            )
            second = AccountResolutionService.resolve_or_create(
                db,
                bank_name="BOB",
                account_type="SAVINGS",
                account_number="OPEN",
                holder_name="Bob",
            )
            db.commit()

            rows = db.scalars(select(BankAccount).order_by(BankAccount.id)).all()
            assert first.id == second.id
            assert len(rows) == 1
            assert rows[0].account_number is None
        finally:
            db.close()