import logging
from pathlib import Path

from app.config import settings
from app.models.enums import BankType, StatementType
from app.parsers.base_parser import ParseException, ParseResult
from app.parsing.extraction.artifacts import ExtractedPageTables, ExtractedTextDocument
from app.parsing.extraction.pdf_tables import extract_pdf_tables
from app.parsing.extraction.pdf_text import extract_pdf_text, extract_text_document
from app.parsing.result_selection import result_transaction_count, select_best_result
from app.parsing.routing import resolve_strategy_route
from app.parsing.strategies.multiline_strategy import (
    try_cc_multiline_strategy,
    try_cc_simple_multiline_strategy,
    try_multiline_strategy,
)
from app.parsing.strategies.single_line_strategy import try_single_line_strategy
from app.parsing.strategies.table_strategy import try_table_strategy

logger = logging.getLogger(__name__)


def extract_generic_pdf_raw_text(file_path: str | Path, password: str | None = None) -> str:
    return extract_pdf_text(file_path, password=password)


def run_strategy(
    strategy_name: str,
    *,
    page_tables: list[ExtractedPageTables],
    text_document: ExtractedTextDocument,
    statement_type: StatementType,
) -> ParseResult | None:
    if strategy_name == "table":
        return try_table_strategy(page_tables, statement_type)
    if strategy_name == "single_line":
        return try_single_line_strategy(text_document, statement_type)
    if strategy_name == "cc_multiline":
        if statement_type != StatementType.CREDIT_CARD:
            return None
        return try_cc_multiline_strategy(text_document)
    if strategy_name == "cc_simple_multiline":
        if statement_type != StatementType.CREDIT_CARD:
            return None
        return try_cc_simple_multiline_strategy(text_document)
    if strategy_name == "multiline":
        return try_multiline_strategy(text_document, statement_type)

    logger.warning("Unknown strategy name in profile order: %s", strategy_name)
    return None


def parse_generic_pdf_statement(
    file_path: str | Path,
    statement_type: StatementType,
    *,
    password: str | None = None,
    bank: BankType | None = None,
) -> ParseResult:
    file_path = Path(file_path)
    if not file_path.exists():
        raise ParseException(f"File not found: {file_path}")

    try:
        candidate_results: list[ParseResult] = []

        page_tables = extract_pdf_tables(file_path, password=password)
        if not page_tables:
            return ParseResult.failure("PDF has no pages")

        text_document = extract_text_document(file_path, password=password)
        raw_text = text_document.raw_text
        route = resolve_strategy_route(raw_text, statement_type, bank=bank)

        if route.profile is not None:
            logger.info(
                "Resolved strategy profile %s with order %s",
                route.profile_id,
                ", ".join(route.strategy_order),
            )
        else:
            logger.info(
                "Using default strategy route for %s with order %s",
                statement_type.value,
                ", ".join(route.strategy_order),
            )

        if settings.debug:
            try:
                debug_path = Path(file_path).parent / "last_parsed_text.txt"
                debug_path.write_text(raw_text, encoding="utf-8")
                logger.debug("Dumped extracted text to %s", debug_path)
            except Exception:
                pass

        for strategy_name in route.strategy_order:
            result = run_strategy(
                strategy_name,
                page_tables=page_tables,
                text_document=text_document,
                statement_type=statement_type,
            )
            if result and result.success:
                result.strategy = strategy_name
                candidate_results.append(result)

        best_result = select_best_result(candidate_results)
        if best_result is not None:
            logger.info(
                "Selected %s strategy with %s transactions",
                best_result.strategy,
                result_transaction_count(best_result),
            )
            return best_result

        return ParseResult.failure(
            "Could not extract transactions from PDF using "
            "table, single-line text, or multi-line text strategy."
        )
    except ParseException:
        raise
    except Exception as exc:
        raise ParseException(f"Failed to parse PDF: {exc}", cause=exc)


class GenericPdfParser:
    """Parsing-layer generic PDF parser runtime."""

    def parse(
        self,
        file_path: str | Path,
        statement_type: StatementType,
        password: str | None = None,
        bank: BankType | None = None,
    ) -> ParseResult:
        return parse_generic_pdf_statement(
            file_path,
            statement_type,
            password=password,
            bank=bank,
        )

    def extract_raw_text(self, file_path: str | Path, password: str | None = None) -> str:
        return extract_generic_pdf_raw_text(file_path, password=password)