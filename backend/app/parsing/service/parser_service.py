import inspect
import logging
import tempfile
from pathlib import Path
from typing import Any, Callable

from app.config import settings
from app.models.enums import BankType, StatementType
from app.parsing.generic_pdf import GenericPdfParser
from app.parsing.debug.trace import build_trace
from app.parsing.engine import ParsingEngine
from app.parsing.errors import (
    ERROR_INVALID_PDF,
    STAGE_CLEANUP_TEMP_FILE,
    STAGE_EXTRACT_RAW_TEXT,
    STAGE_GENERIC_PARSE,
    STAGE_LLM_FALLBACK,
    STAGE_REVIEW_FALLBACK,
    STAGE_SAVE_TEMP_FILE,
    STAGE_VALIDATE_PDF,
    STAGE_VALIDATE_STATEMENT,
)
from app.parsing.extraction.statement_metadata import extract_statement_metadata
from app.parsing.fallbacks import (
    build_parse_failure_result,
    build_parse_success_result,
    build_review_fallback,
    run_llm_fallback,
)
from app.parsing.validation import validate_statement

logger = logging.getLogger(__name__)
PDF_MAGIC = b"%PDF"


def apply_account_identity(
    statement,
    bank: BankType,
    statement_type: StatementType,
    raw_text: str,
) -> None:
    """Set bank name and extracted identifiers on the parsed statement."""
    metadata = extract_statement_metadata(raw_text) if raw_text else None
    bank_label = bank.value.replace("_", " ").title()

    if statement_type == StatementType.CREDIT_CARD:
        if not getattr(statement, "card_holder_name", None):
            statement.card_holder_name = bank_label
        if not getattr(statement, "card_number", None) and metadata and metadata.card_number:
            statement.card_number = metadata.card_number
    else:
        if not getattr(statement, "account_holder_name", None):
            statement.account_holder_name = bank_label
        if not getattr(statement, "account_number", None) and metadata and metadata.account_number:
            statement.account_number = metadata.account_number


def format_failure_error(
    *,
    bank: BankType,
    statement_type: StatementType,
    generic_error: str,
    llm_status: str,
    llm_error: str | None,
) -> str:
    """Build a user-facing parse failure message with generic and LLM detail."""
    message = (
        f"Failed to parse {bank.value}/{statement_type.value} statement: "
        f"Generic parser failed: {generic_error}"
    )

    if llm_status == "attempted" and llm_error:
        return f"{message}. LLM fallback failed: {llm_error}"
    if llm_error:
        return f"{message}. {llm_error}"
    return message


def validate_upload(file_content: bytes, *, settings_obj) -> None:
    """Validate uploaded file size using runtime settings or safe defaults."""
    max_upload_size_bytes = getattr(settings_obj, "max_upload_size_bytes", 10 * 1024 * 1024)
    max_upload_size_mb = getattr(settings_obj, "max_upload_size_mb", 10)
    if len(file_content) > max_upload_size_bytes:
        raise ValueError(f"File too large. Max allowed is {max_upload_size_mb}MB")


def validate_pdf(file_content: bytes, *, settings_obj) -> None:
    """Validate uploaded file (size + PDF magic)."""
    validate_upload(file_content, settings_obj=settings_obj)
    if not file_content[:4].startswith(PDF_MAGIC):
        raise ValueError("Uploaded file is not a valid PDF")


def save_temp_file(content: bytes, prefix: str = "upload-") -> str:
    """Save content to a temp file and return its path."""
    tmp = tempfile.NamedTemporaryFile(prefix=prefix, suffix=".pdf", delete=False)
    tmp.write(content)
    tmp.close()
    return tmp.name


class ParserService:
    def __init__(
        self,
        *,
        parser_cls=None,
        settings_obj=None,
        validate_pdf_fn: Callable[[bytes], None] | None = None,
        save_temp_file_fn: Callable[[bytes, str], str] | None = None,
        apply_account_identity_fn: Callable[[Any, BankType, StatementType, str], None] | None = None,
        format_failure_error_fn: Callable[..., str] | None = None,
    ):
        self._parser_cls = parser_cls or GenericPdfParser
        self._settings = settings_obj or settings
        self._validate_pdf = validate_pdf_fn or (
            lambda file_content: validate_pdf(file_content, settings_obj=self._settings)
        )
        self._save_temp_file = save_temp_file_fn or save_temp_file
        self._apply_account_identity = apply_account_identity_fn or apply_account_identity
        self._format_failure_error = format_failure_error_fn or format_failure_error

    async def parse_statement(
        self,
        file_content: bytes,
        filename: str,
        bank: BankType,
        statement_type: StatementType,
        password: str | None = None,
    ) -> dict:
        result, trace = await self.parse_statement_with_trace(
            file_content=file_content,
            filename=filename,
            bank=bank,
            statement_type=statement_type,
            password=password,
        )
        result["trace"] = trace.to_dict()
        return result

    async def parse_statement_with_trace(
        self,
        file_content: bytes,
        filename: str,
        bank: BankType,
        statement_type: StatementType,
        password: str | None = None,
    ) -> tuple[dict, Any]:
        trace = build_trace(
            filename=filename,
            bank=bank,
            statement_type=statement_type,
            password_supplied=bool(password),
        )
        engine = ParsingEngine(trace)

        try:
            self._validate_pdf(file_content)
            engine.stage(STAGE_VALIDATE_PDF, "ok")
        except Exception as exc:
            engine.stage(STAGE_VALIDATE_PDF, "failed", str(exc))
            engine.fail(stage=STAGE_VALIDATE_PDF, code=ERROR_INVALID_PDF, message=str(exc))
            raise

        tmp_path: str | None = None
        try:
            tmp_path = self._save_temp_file(
                file_content,
                prefix=f"{bank.value.lower()}-upload-",
            )
            engine.stage(STAGE_SAVE_TEMP_FILE, "ok", tmp_path)

            parser = self._parser_cls()
            raw_text = ""
            statement_metadata = None

            try:
                raw_text = parser.extract_raw_text(tmp_path, password=password)
                statement_metadata = extract_statement_metadata(raw_text) if raw_text else None
                engine.stage(STAGE_EXTRACT_RAW_TEXT, "ok", f"{len(raw_text)} chars")
            except Exception as exc:
                engine.stage(STAGE_EXTRACT_RAW_TEXT, "warning", str(exc))

            llm_status = "not_attempted"
            llm_error = None

            result = self._parse_with_optional_bank(
                parser,
                tmp_path,
                statement_type,
                password=password,
                bank=bank,
            )
            generic_error = result.error_message or "0 transactions found"

            if result.success and result.result:
                txn_count = len(getattr(result.result, "transactions", []))
                if txn_count > 0:
                    self._apply_account_identity(
                        result.result,
                        bank,
                        statement_type,
                        raw_text,
                    )
                    validation = validate_statement(
                        result.result,
                        statement_type,
                        metadata=statement_metadata,
                    )
                    trace.set_validation(validation)
                    review_fallback = build_review_fallback(validation)
                    validation_message = self._format_validation_message(validation)
                    engine.stage(
                        STAGE_VALIDATE_STATEMENT,
                        "ok" if validation.trusted else "warning",
                        validation_message,
                    )
                    if review_fallback is not None:
                        engine.stage(
                            STAGE_REVIEW_FALLBACK,
                            "warning",
                            review_fallback.message,
                        )
                    engine.stage(STAGE_GENERIC_PARSE, "ok", f"{txn_count} transactions")
                    engine.attempt(
                        "generic",
                        "success",
                        strategy=result.strategy,
                        message=f"{txn_count} transactions",
                    )
                    logger.info("Generic parser succeeded: %s transactions", txn_count)
                    return (
                        build_parse_success_result(
                            statement=result.result,
                            raw_text=raw_text,
                            parser_name="generic",
                            strategy=result.strategy,
                            validation=validation,
                            review_fallback=review_fallback,
                        ),
                        trace,
                    )

            engine.stage(STAGE_GENERIC_PARSE, "warning", generic_error)
            engine.attempt(
                "generic",
                "failed",
                strategy=result.strategy,
                message=generic_error,
            )
            logger.warning(
                "Generic parser insufficient (%s), trying LLM fallback...",
                generic_error,
            )

            llm_outcome = run_llm_fallback(
                raw_text,
                bank,
                statement_type,
                llm_provider=self._settings.llm_provider,
            )
            llm_status = llm_outcome.status
            llm_error = llm_outcome.error

            if llm_status.startswith("skipped"):
                engine.stage(STAGE_LLM_FALLBACK, "skipped", llm_error)
                engine.attempt("llm", "skipped", strategy="llm", message=llm_error)
            elif llm_outcome.exception_message is not None:
                engine.stage(STAGE_LLM_FALLBACK, "failed", llm_error)
                engine.attempt(
                    "llm",
                    "failed",
                    strategy="llm",
                    message=llm_error,
                )
                logger.warning("LLM fallback error: %s", llm_error)
            else:
                llm_result = llm_outcome.parse_result
                if llm_result and llm_result.success and llm_result.result:
                    txn_count = len(getattr(llm_result.result, "transactions", []))
                    if txn_count > 0:
                        self._apply_account_identity(
                            llm_result.result,
                            bank,
                            statement_type,
                            raw_text,
                        )
                        validation = validate_statement(
                            llm_result.result,
                            statement_type,
                            metadata=statement_metadata,
                        )
                        trace.set_validation(validation)
                        review_fallback = build_review_fallback(validation)
                        validation_message = self._format_validation_message(validation)
                        engine.stage(
                            STAGE_VALIDATE_STATEMENT,
                            "ok" if validation.trusted else "warning",
                            validation_message,
                        )
                        if review_fallback is not None:
                            engine.stage(
                                STAGE_REVIEW_FALLBACK,
                                "warning",
                                review_fallback.message,
                            )
                        engine.stage(STAGE_LLM_FALLBACK, "ok", f"{txn_count} transactions")
                        engine.attempt(
                            "llm",
                            "success",
                            strategy="llm",
                            message=f"{txn_count} transactions",
                        )
                        logger.info("LLM fallback succeeded: %s transactions", txn_count)
                        return (
                            build_parse_success_result(
                                statement=llm_result.result,
                                raw_text=raw_text,
                                parser_name="llm",
                                strategy="llm",
                                validation=validation,
                                review_fallback=review_fallback,
                            ),
                            trace,
                        )

                engine.stage(STAGE_LLM_FALLBACK, "warning", llm_error)
                engine.attempt(
                    "llm",
                    "failed",
                    strategy="llm",
                    message=llm_error,
                )
                logger.warning("LLM fallback also failed: %s", llm_error)

            failure_message = self._format_failure_error(
                bank=bank,
                statement_type=statement_type,
                generic_error=generic_error,
                llm_status=llm_status,
                llm_error=llm_error,
            )
            failure_result = build_parse_failure_result(
                message=failure_message,
                raw_text=raw_text,
                generic_error=generic_error,
                llm_status=llm_status,
                llm_error=llm_error,
            )
            engine.fail(
                stage=failure_result.stage,
                code=failure_result.code,
                message=failure_message,
            )

            return (
                failure_result.payload,
                trace,
            )
        finally:
            if tmp_path is not None:
                Path(tmp_path).unlink(missing_ok=True)
                engine.stage(STAGE_CLEANUP_TEMP_FILE, "ok")

    @staticmethod
    def _format_validation_message(validation) -> str:
        summary = validation.summary()
        failed_codes = summary["failed_codes"]
        if not failed_codes:
            return f"{summary['status']} ({summary['confidence']} confidence)"
        return (
            f"{summary['status']} ({summary['confidence']} confidence): "
            + ", ".join(failed_codes)
        )

    @staticmethod
    def _parse_with_optional_bank(
        parser,
        file_path: str,
        statement_type: StatementType,
        *,
        password: str | None,
        bank: BankType,
    ):
        try:
            parameters = inspect.signature(parser.parse).parameters
        except (TypeError, ValueError):
            parameters = {}

        if "bank" in parameters:
            return parser.parse(file_path, statement_type, password=password, bank=bank)
        return parser.parse(file_path, statement_type, password=password)