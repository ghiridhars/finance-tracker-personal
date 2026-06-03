from datetime import date
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsing.validation import (
    CODE_BALANCE_RECONCILIATION_FAILED,
    CODE_DATES_OUT_OF_RANGE,
    validate_statement,
)
from app.parsing.extraction.artifacts import ExtractedStatementMetadata
from app.schemas.credit_card import CreditCardStatementSchema, CreditCardTransactionSchema
from app.schemas.savings_account import (
    SavingsAccountStatementSchema,
    SavingsAccountTransactionSchema,
)


class TestStatementValidation:
    def test_savings_statement_can_be_trusted(self):
        statement = SavingsAccountStatementSchema(
            from_date=date(2024, 1, 1),
            to_date=date(2024, 1, 31),
            opening_balance=Decimal("100.00"),
            closing_balance=Decimal("130.00"),
            transactions=[
                SavingsAccountTransactionSchema(
                    date=date(2024, 1, 5),
                    deposit_amount=Decimal("40.00"),
                    type=TransactionType.CREDIT,
                ),
                SavingsAccountTransactionSchema(
                    date=date(2024, 1, 8),
                    withdrawal_amount=Decimal("10.00"),
                    type=TransactionType.DEBIT,
                ),
            ],
        )

        report = validate_statement(statement, StatementType.SAVINGS)

        assert report.trusted is True
        assert all(check.status == "passed" for check in report.checks)
        assert report.summary()["confidence"] == "high"

    def test_savings_balance_reconciliation_failure_marks_untrusted(self):
        statement = SavingsAccountStatementSchema(
            from_date=date(2024, 1, 1),
            to_date=date(2024, 1, 31),
            opening_balance=Decimal("100.00"),
            closing_balance=Decimal("999.00"),
            transactions=[
                SavingsAccountTransactionSchema(
                    date=date(2024, 1, 5),
                    deposit_amount=Decimal("40.00"),
                    type=TransactionType.CREDIT,
                )
            ],
        )

        report = validate_statement(statement, StatementType.SAVINGS)

        assert report.trusted is False
        assert CODE_BALANCE_RECONCILIATION_FAILED in report.failed_codes()
        assert report.summary()["status"] == "review_required"
        assert report.summary()["confidence"] == "low"

    def test_credit_card_statement_date_violation_marks_untrusted(self):
        statement = CreditCardStatementSchema(
            statement_date=date(2024, 2, 10),
            transactions=[
                CreditCardTransactionSchema(
                    date=date(2024, 2, 12),
                    amount=Decimal("50.00"),
                    type=TransactionType.DEBIT,
                )
            ],
        )

        report = validate_statement(statement, StatementType.CREDIT_CARD)

        assert report.trusted is False
        assert CODE_DATES_OUT_OF_RANGE in report.failed_codes()

    def test_savings_validation_uses_metadata_period_when_statement_dates_are_wrong(self):
        statement = SavingsAccountStatementSchema(
            from_date=date(2024, 1, 15),
            to_date=date(2024, 1, 15),
            opening_balance=Decimal("100.00"),
            closing_balance=Decimal("120.00"),
            transactions=[
                SavingsAccountTransactionSchema(
                    date=date(2024, 1, 20),
                    deposit_amount=Decimal("20.00"),
                    type=TransactionType.CREDIT,
                )
            ],
        )

        report = validate_statement(
            statement,
            StatementType.SAVINGS,
            metadata=ExtractedStatementMetadata(
                period_from="01/01/2024",
                period_to="31/01/2024",
            ),
        )

        assert report.trusted is True
        date_range_check = next(check for check in report.checks if check.name == "date_range")
        assert date_range_check.status == "passed"
        assert "metadata period" in (date_range_check.message or "")
        assert report.summary()["confidence"] == "high"

    def test_credit_card_validation_uses_metadata_period(self):
        statement = CreditCardStatementSchema(
            statement_date=None,
            transactions=[
                CreditCardTransactionSchema(
                    date=date(2024, 2, 9),
                    amount=Decimal("50.00"),
                    type=TransactionType.DEBIT,
                )
            ],
        )

        report = validate_statement(
            statement,
            StatementType.CREDIT_CARD,
            metadata=ExtractedStatementMetadata(
                period_from="01/02/2024",
                period_to="10/02/2024",
            ),
        )

        assert report.trusted is True
        date_range_check = next(check for check in report.checks if check.name == "date_range")
        assert date_range_check.status == "passed"
        assert "metadata period" in (date_range_check.message or "")
        assert report.summary()["confidence"] == "high"

    def test_validation_summary_is_medium_when_checks_are_skipped(self):
        statement = SavingsAccountStatementSchema(
            transactions=[
                SavingsAccountTransactionSchema(
                    date=date(2024, 3, 1),
                    deposit_amount=Decimal("25.00"),
                    type=TransactionType.CREDIT,
                )
            ],
        )

        report = validate_statement(statement, StatementType.SAVINGS)

        assert report.trusted is True
        assert report.summary()["status"] == "trusted"
        assert report.summary()["confidence"] == "medium"
        assert report.summary()["check_counts"] == {"passed": 1, "failed": 0, "skipped": 2}