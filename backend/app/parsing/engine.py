from app.parsing.debug.trace import record_attempt, record_failure, record_stage
from app.parsing.models import ParseTrace


class ParsingEngine:
    def __init__(self, trace: ParseTrace):
        self.trace = trace

    def stage(self, stage: str, status: str, message: str | None = None):
        return record_stage(self.trace, stage=stage, status=status, message=message)

    def attempt(
        self,
        parser: str,
        status: str,
        *,
        strategy: str | None = None,
        message: str | None = None,
    ):
        return record_attempt(
            self.trace,
            parser=parser,
            status=status,
            strategy=strategy,
            message=message,
        )

    def fail(self, *, stage: str, code: str, message: str):
        return record_failure(self.trace, stage=stage, code=code, message=message)