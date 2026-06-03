from datetime import date
from decimal import Decimal

from app.models.enums import StatementType, TransactionType
from app.parsing.result_builders import (
    build_credit_card_result,
    build_result,
    build_savings_result,
)


class TestResultBuilders:
    def test_build_savings_result_keeps_explicit_opening_balance(self):
        result = build_savings_result(
            [
                {
                    "date": date(2024, 1, 15),
                    "description": "ATM",
                    "reference": None,
                    "debit": Decimal("2000"),
                    "credit": None,
                    "balance": Decimal("48000"),
                    "type": TransactionType.DEBIT,
                },
                {
                    "date": date(2024, 1, 20),
                    "description": "SALARY",
                    "reference": None,
                    "debit": None,
                    "credit": Decimal("50000"),
                    "balance": Decimal("98000"),
                    "type": TransactionType.CREDIT,
                },
            ],
            opening_balance=Decimal("50000"),
        )

        assert result.success
        assert result.result.opening_balance == Decimal("50000")
        assert result.result.from_date == date(2024, 1, 15)
        assert result.result.to_date == date(2024, 1, 20)

    def test_build_savings_result_infers_opening_balance(self):
        result = build_savings_result(
            [
                {
                    "date": date(2024, 1, 15),
                    "description": "DEBIT",
                    "reference": None,
                    "debit": Decimal("2000"),
                    "credit": None,
                    "balance": Decimal("48000"),
                    "type": TransactionType.DEBIT,
                }
            ]
        )

        assert result.success
        assert result.result.opening_balance == Decimal("50000")

    def test_build_credit_card_result_sets_statement_date(self):
        result = build_credit_card_result(
            [
                {
                    "date": date(2024, 2, 5),
                    "description": "AMAZON",
                    "reference": "REF123",
                    "debit": Decimal("1500"),
                    "credit": None,
                    "balance": None,
                    "type": TransactionType.DEBIT,
                },
                {
                    "date": date(2024, 2, 10),
                    "description": "PAYMENT",
                    "reference": None,
                    "debit": None,
                    "credit": Decimal("5000"),
                    "balance": None,
                    "type": TransactionType.CREDIT,
                },
            ]
        )

        assert result.success
        assert result.result.statement_date == date(2024, 2, 10)

    def test_build_result_rejects_empty_transactions(self):
        result = build_result([], StatementType.SAVINGS)

        assert not result.success
        assert "No transactions" in result.error_message