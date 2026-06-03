from dataclasses import asdict, dataclass, field
from typing import Literal

from app.models.enums import BankType, StatementType

StageStatus = Literal["ok", "warning", "failed", "skipped"]
AttemptStatus = Literal["success", "failed", "skipped"]
ValidationStatus = Literal["passed", "failed", "skipped"]


@dataclass(frozen=True, slots=True)
class ParseContext:
    filename: str
    bank: BankType
    statement_type: StatementType
    password_supplied: bool = False


@dataclass(frozen=True, slots=True)
class ParseFailure:
    stage: str
    code: str
    owner: str
    message: str


@dataclass(frozen=True, slots=True)
class StageEvent:
    stage: str
    status: StageStatus
    owner: str
    message: str | None = None


@dataclass(frozen=True, slots=True)
class ParseAttempt:
    parser: str
    status: AttemptStatus
    strategy: str | None = None
    message: str | None = None


@dataclass(frozen=True, slots=True)
class ValidationCheck:
    name: str
    status: ValidationStatus
    code: str | None = None
    message: str | None = None


@dataclass(slots=True)
class ValidationReport:
    trusted: bool = True
    checks: list[ValidationCheck] = field(default_factory=list)

    def add_check(
        self,
        *,
        name: str,
        status: ValidationStatus,
        code: str | None = None,
        message: str | None = None,
    ) -> ValidationCheck:
        check = ValidationCheck(name=name, status=status, code=code, message=message)
        self.checks.append(check)
        if status == "failed":
            self.trusted = False
        return check

    def failed_codes(self) -> list[str]:
        return [check.code for check in self.checks if check.status == "failed" and check.code]

    def summary(self) -> dict:
        passed = sum(1 for check in self.checks if check.status == "passed")
        failed = sum(1 for check in self.checks if check.status == "failed")
        skipped = sum(1 for check in self.checks if check.status == "skipped")

        if failed:
            confidence = "low"
        elif passed and not skipped:
            confidence = "high"
        elif passed or skipped:
            confidence = "medium"
        else:
            confidence = "unknown"

        return {
            "status": "trusted" if self.trusted else "review_required",
            "confidence": confidence,
            "check_counts": {
                "passed": passed,
                "failed": failed,
                "skipped": skipped,
            },
            "failed_codes": self.failed_codes(),
        }

    def to_dict(self) -> dict:
        data = asdict(self)
        data["summary"] = self.summary()
        return data


@dataclass(slots=True)
class ParseTrace:
    context: ParseContext
    events: list[StageEvent] = field(default_factory=list)
    attempts: list[ParseAttempt] = field(default_factory=list)
    failure: ParseFailure | None = None
    validation: ValidationReport | None = None

    def add_event(
        self,
        *,
        stage: str,
        status: StageStatus,
        owner: str,
        message: str | None = None,
    ) -> StageEvent:
        event = StageEvent(stage=stage, status=status, owner=owner, message=message)
        self.events.append(event)
        return event

    def add_attempt(
        self,
        *,
        parser: str,
        status: AttemptStatus,
        strategy: str | None = None,
        message: str | None = None,
    ) -> ParseAttempt:
        attempt = ParseAttempt(
            parser=parser,
            status=status,
            strategy=strategy,
            message=message,
        )
        self.attempts.append(attempt)
        return attempt

    def set_failure(self, *, stage: str, code: str, owner: str, message: str) -> ParseFailure:
        failure = ParseFailure(stage=stage, code=code, owner=owner, message=message)
        self.failure = failure
        return failure

    def set_validation(self, report: ValidationReport) -> ValidationReport:
        self.validation = report
        return report

    def to_dict(self) -> dict:
        data = asdict(self)
        context = data["context"]
        context["bank"] = self.context.bank.value
        context["statement_type"] = self.context.statement_type.value
        if self.validation is not None:
            data["validation"] = self.validation.to_dict()
        return data