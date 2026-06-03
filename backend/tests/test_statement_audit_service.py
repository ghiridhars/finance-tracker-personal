import json
from datetime import date
from decimal import Decimal
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models.bank_account import BankAccount
from app.models.enums import StatementType
from app.models.statement_audit import StatementAudit
from app.models.transaction import UnifiedTransaction
from app.services.statement_audit_service import StatementAuditService


def _make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(
        bind=engine,
        tables=[
            BankAccount.__table__,
            StatementAudit.__table__,
            UnifiedTransaction.__table__,
        ],
    )
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return session_factory()


class TestStatementAuditService:
    def test_record_serializes_parse_trace(self):
        db = _make_session()
        try:
            audit = StatementAuditService.record(
                db,
                file_name="statement.pdf",
                file_content=b"%PDF-1.4",
                bank_name="BOB",
                statement_type="SAVINGS",
                status="FAILED",
                error_message="boom",
                parse_trace={"context": {"filename": "statement.pdf"}},
                source="upload",
            )
            db.commit()

            stored = db.get(StatementAudit, audit.id)
            assert stored is not None
            assert json.loads(stored.parse_trace) == {
                "context": {"filename": "statement.pdf"}
            }
        finally:
            db.close()

    def test_save_statement_persists_parse_trace(self, monkeypatch):
        db = _make_session()
        try:
            account = BankAccount(
                name="Bob Savings",
                bank_name="BOB",
                account_type="SAVINGS",
                account_number="1234",
                holder_name="Bob",
            )
            db.add(account)
            db.commit()

            monkeypatch.setattr(
                "app.services.transaction_service.UnifiedTransactionService.create_from_parsed",
                lambda *args, **kwargs: None,
            )

            dto = SimpleNamespace(
                from_date=date(2025, 1, 1),
                to_date=date(2025, 1, 31),
                opening_balance=Decimal("100.00"),
                closing_balance=Decimal("250.00"),
                account_holder_name="Bob",
                account_number="1234",
                ifsc_code=None,
                branch_name=None,
                transactions=[SimpleNamespace(), SimpleNamespace()],
            )

            audit = StatementAuditService.save_statement(
                db,
                dto,
                statement_type=StatementType.SAVINGS,
                bank_account_id=account.id,
                bank_name="BOB",
                file_name="statement.pdf",
                file_content=b"%PDF-1.4",
                parser_strategy="multiline",
                parse_trace={"events": [{"stage": "generic_parse", "status": "ok"}]},
                source="upload",
            )

            assert json.loads(audit.parse_trace) == {
                "events": [{"stage": "generic_parse", "status": "ok"}]
            }
        finally:
            db.close()