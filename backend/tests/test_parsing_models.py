from app.models.enums import BankType, StatementType
from app.parsing.models import ParseContext, ParseTrace, ValidationReport


def test_parse_trace_serializes_enum_context_values():
    trace = ParseTrace(
        context=ParseContext(
            filename="statement.pdf",
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
            password_supplied=True,
        )
    )

    data = trace.to_dict()

    assert data["context"]["bank"] == "BOB"
    assert data["context"]["statement_type"] == "SAVINGS"
    assert data["context"]["password_supplied"] is True


def test_parse_trace_tracks_events_attempts_and_failure():
    trace = ParseTrace(
        context=ParseContext(
            filename="statement.pdf",
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )
    )

    trace.add_event(stage="validate_pdf", status="ok", owner="tests")
    trace.add_attempt(parser="generic", status="success", strategy="table")
    trace.set_failure(stage="generic_parse", code="parser.generic_parse_failed", owner="tests", message="boom")

    assert trace.events[0].stage == "validate_pdf"
    assert trace.attempts[0].strategy == "table"
    assert trace.failure is not None
    assert trace.failure.code == "parser.generic_parse_failed"


def test_parse_trace_serializes_validation_report():
    trace = ParseTrace(
        context=ParseContext(
            filename="statement.pdf",
            bank=BankType.BOB,
            statement_type=StatementType.SAVINGS,
        )
    )
    validation = ValidationReport()
    validation.add_check(name="transaction_count", status="passed", message="1 transaction")
    trace.set_validation(validation)

    data = trace.to_dict()

    assert data["validation"]["trusted"] is True
    assert data["validation"]["checks"][0]["name"] == "transaction_count"
    assert data["validation"]["summary"]["status"] == "trusted"
    assert data["validation"]["summary"]["confidence"] == "high"