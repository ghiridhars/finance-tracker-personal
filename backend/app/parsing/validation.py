from decimal import Decimal

from app.models.enums import StatementType
from app.parsing.patterns import parse_date
from app.parsing.extraction.artifacts import ExtractedStatementMetadata
from app.parsing.models import ValidationReport

CHECK_TRANSACTION_COUNT = "transaction_count"
CHECK_BALANCE_RECONCILIATION = "balance_reconciliation"
CHECK_DATE_RANGE = "date_range"

CODE_NO_TRANSACTIONS = "validate.statement.no_transactions"
CODE_BALANCE_RECONCILIATION_FAILED = "validate.balance.reconciliation_failed"
CODE_DATES_OUT_OF_RANGE = "validate.dates.out_of_range"


def validate_statement(
    statement,
    statement_type: StatementType,
    metadata: ExtractedStatementMetadata | None = None,
) -> ValidationReport:
    report = ValidationReport()
    transactions = list(getattr(statement, "transactions", []) or [])

    if transactions:
        report.add_check(
            name=CHECK_TRANSACTION_COUNT,
            status="passed",
            message=f"{len(transactions)} transactions",
        )
    else:
        report.add_check(
            name=CHECK_TRANSACTION_COUNT,
            status="failed",
            code=CODE_NO_TRANSACTIONS,
            message="No transactions found.",
        )

    if statement_type == StatementType.SAVINGS:
        _validate_savings_balance(statement, report)
        _validate_savings_date_range(statement, report, metadata)
    else:
        _validate_credit_card_statement_date(statement, report, metadata)

    return report


def _validate_savings_balance(statement, report: ValidationReport) -> None:
    opening_balance = getattr(statement, "opening_balance", None)
    closing_balance = getattr(statement, "closing_balance", None)
    if opening_balance is None or closing_balance is None:
        report.add_check(
            name=CHECK_BALANCE_RECONCILIATION,
            status="skipped",
            message="Opening or closing balance missing.",
        )
        return

    expected_closing = opening_balance
    zero = Decimal("0")
    mismatched_indices = []
    valid_indices = []

    for idx, transaction in enumerate(getattr(statement, "transactions", []) or []):
        withdrawal = getattr(transaction, "withdrawal_amount", None) or zero
        deposit = getattr(transaction, "deposit_amount", None) or zero
        expected_closing = expected_closing - withdrawal + deposit

        actual_step_balance = getattr(transaction, "closing_balance", None)
        if actual_step_balance is not None and actual_step_balance != expected_closing:
            mismatched_indices.append(idx)
        else:
            valid_indices.append(idx)

    report.valid_indices = valid_indices
    report.mismatched_indices = mismatched_indices

    if expected_closing == closing_balance:
        report.add_check(
            name=CHECK_BALANCE_RECONCILIATION,
            status="passed",
            message="Opening balance reconciles to closing balance.",
        )
        return

    report.add_check(
        name=CHECK_BALANCE_RECONCILIATION,
        status="failed",
        code=CODE_BALANCE_RECONCILIATION_FAILED,
        message=(
            f"Expected closing balance {expected_closing} but found {closing_balance}. "
            f"{len(mismatched_indices)} transaction step(s) mismatched."
        ),
    )


def _validate_savings_date_range(
    statement,
    report: ValidationReport,
    metadata: ExtractedStatementMetadata | None,
) -> None:
    metadata_from, metadata_to = _metadata_period_bounds(metadata)
    from_date = metadata_from or getattr(statement, "from_date", None)
    to_date = metadata_to or getattr(statement, "to_date", None)
    transaction_dates = [
        txn_date
        for transaction in getattr(statement, "transactions", []) or []
        if (txn_date := getattr(transaction, "date", None)) is not None
    ]

    boundary_source = "metadata period" if metadata_from or metadata_to else "statement period"

    if from_date is None or to_date is None or not transaction_dates:
        report.add_check(
            name=CHECK_DATE_RANGE,
            status="skipped",
            message=f"{boundary_source.title()} or transaction dates missing.",
        )
        return

    if min(transaction_dates) < from_date or max(transaction_dates) > to_date:
        report.add_check(
            name=CHECK_DATE_RANGE,
            status="failed",
            code=CODE_DATES_OUT_OF_RANGE,
            message=f"Transaction dates fall outside the {boundary_source}.",
        )
        return

    report.add_check(
        name=CHECK_DATE_RANGE,
        status="passed",
        message=f"Transaction dates are within the {boundary_source}.",
    )


def _validate_credit_card_statement_date(
    statement,
    report: ValidationReport,
    metadata: ExtractedStatementMetadata | None,
) -> None:
    metadata_from, metadata_to = _metadata_period_bounds(metadata)
    statement_date = metadata_to or getattr(statement, "statement_date", None)
    transaction_dates = [
        txn_date
        for transaction in getattr(statement, "transactions", []) or []
        if (txn_date := getattr(transaction, "date", None)) is not None
    ]

    boundary_source = "metadata period" if metadata_from or metadata_to else "statement date"

    if statement_date is None or not transaction_dates:
        report.add_check(
            name=CHECK_DATE_RANGE,
            status="skipped",
            message=f"{boundary_source.title()} or transaction dates missing.",
        )
        return

    if metadata_from is not None and min(transaction_dates) < metadata_from:
        report.add_check(
            name=CHECK_DATE_RANGE,
            status="failed",
            code=CODE_DATES_OUT_OF_RANGE,
            message="Transaction dates fall outside the metadata period.",
        )
        return

    if max(transaction_dates) > statement_date:
        report.add_check(
            name=CHECK_DATE_RANGE,
            status="failed",
            code=CODE_DATES_OUT_OF_RANGE,
            message=(
                "Transaction dates fall outside the metadata period."
                if metadata_to is not None
                else "Transaction dates fall after the statement date."
            ),
        )
        return

    report.add_check(
        name=CHECK_DATE_RANGE,
        status="passed",
        message=(
            "Transaction dates are within the metadata period."
            if metadata_from or metadata_to
            else "Transaction dates are within the statement date boundary."
        ),
    )


def _metadata_period_bounds(
    metadata: ExtractedStatementMetadata | None,
) -> tuple[object | None, object | None]:
    if metadata is None:
        return None, None
    metadata_from = parse_date(metadata.period_from) if metadata.period_from else None
    metadata_to = parse_date(metadata.period_to) if metadata.period_to else None
    return metadata_from, metadata_to