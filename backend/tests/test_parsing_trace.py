from app.models.enums import BankType, StatementType
from app.parsing.debug.trace import build_trace, record_attempt, record_failure, record_stage


def test_build_trace_sets_context_and_stage_owners():
    trace = build_trace(
        filename="statement.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_supplied=False,
    )

    event = record_stage(trace, stage="generic_parse", status="warning", message="0 transactions found")
    validate_event = record_stage(trace, stage="validate_pdf", status="ok")

    assert trace.context.filename == "statement.pdf"
    assert trace.context.bank == BankType.HDFC
    assert event.owner == "app.parsers.generic_pdf_parser"
    assert validate_event.owner == "app.parsing.service.parser_service"


def test_record_attempt_and_failure_use_trace_container():
    trace = build_trace(
        filename="statement.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        password_supplied=True,
    )

    record_attempt(trace, parser="generic", status="failed", strategy="multiline", message="0 transactions found")
    failure = record_failure(
        trace,
        stage="generic_parse",
        code="parser.generic_parse_failed",
        message="Failed to parse statement.",
    )

    assert trace.attempts[0].parser == "generic"
    assert trace.attempts[0].strategy == "multiline"
    assert failure.owner == "app.parsers.generic_pdf_parser"
    assert trace.failure is failure