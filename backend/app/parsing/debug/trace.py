from app.models.enums import BankType, StatementType
from app.parsing.errors import owner_for_stage
from app.parsing.models import ParseContext, ParseTrace


def build_trace(
    *,
    filename: str,
    bank: BankType,
    statement_type: StatementType,
    password_supplied: bool,
) -> ParseTrace:
    return ParseTrace(
        context=ParseContext(
            filename=filename,
            bank=bank,
            statement_type=statement_type,
            password_supplied=password_supplied,
        )
    )


def record_stage(
    trace: ParseTrace,
    *,
    stage: str,
    status: str,
    message: str | None = None,
):
    return trace.add_event(
        stage=stage,
        status=status,
        owner=owner_for_stage(stage),
        message=message,
    )


def record_attempt(
    trace: ParseTrace,
    *,
    parser: str,
    status: str,
    strategy: str | None = None,
    message: str | None = None,
):
    return trace.add_attempt(
        parser=parser,
        status=status,
        strategy=strategy,
        message=message,
    )


def record_failure(
    trace: ParseTrace,
    *,
    stage: str,
    code: str,
    message: str,
):
    return trace.set_failure(
        stage=stage,
        code=code,
        owner=owner_for_stage(stage),
        message=message,
    )