"""
Parser orchestration service.
Replaces: app.personal.service.ParserService (Java @Service)

Handles file validation, temp file management, parser invocation,
and LLM fallback when regex parsing fails.

Uses the parser registry to dispatch to the correct parser based on
(BankType, StatementType). Falls back to generic LLM parsing for
unregistered bank/statement combinations.

FIX: Consistent 10MB upload limit (Java version had conflicting limits
     between Spring defaults and ParserService).
"""
import logging
import tempfile
from pathlib import Path

from app.config import settings
from app.models.enums import BankType, StatementType
from app.parsers.base_parser import ParseException, ParserProfile
from app.parsers.parser_registry import get_parser, has_parser
from app.schemas.credit_card import CreditCardStatementSchema
from app.schemas.savings_account import SavingsAccountStatementSchema

logger = logging.getLogger(__name__)

# PDF magic bytes
PDF_MAGIC = b"%PDF"


class ParserService:
    """
    Replaces: ParserService.java

    Orchestrates file upload validation, temp file handling,
    parser invocation, and LLM fallback for different bank statement types.

    Now uses the parser registry for dispatch instead of hardcoded parser references.
    """

    # ── Unified entry point (new) ──────────────────────────────

    async def parse_statement(
        self,
        file_content: bytes,
        filename: str,
        bank: BankType,
        statement_type: StatementType,
    ) -> dict:
        """
        Unified parse entry point. Dispatches to the correct parser via registry.
        Falls back to generic LLM if no regex parser is registered.

        Returns a dict with:
          - success: bool
          - statement: parsed schema (or None)
          - rawText: raw PDF text
          - parser: "regex" | "llm"
          - error: error message (if failed)
        """
        self._validate_upload(file_content)
        tmp_path = self._save_temp_file(file_content, prefix=f"{bank.value.lower()}-upload-")

        try:
            # Extract raw text for LLM fallback / debug
            raw_text = ""
            parser = get_parser(bank, statement_type)

            if parser:
                try:
                    raw_text = parser.extract_raw_text(tmp_path)
                except Exception:
                    pass

            response: dict = {}

            # Step 1: Try regex parser from registry
            if parser:
                profile = self._load_parser_profile(f"{bank.value.lower()}-profile.yml")
                if profile:
                    result = parser.parse_by_area(tmp_path, profile)
                else:
                    result = parser.parse(tmp_path)

                if result.success and result.result:
                    txn_count = len(getattr(result.result, "transactions", []))
                    if txn_count > 0:
                        logger.info(f"Regex parser succeeded: {txn_count} transactions")
                        return {
                            "success": True,
                            "statement": result.result,
                            "rawText": raw_text,
                            "parser": "regex",
                        }

                regex_error = result.error_message or "0 transactions found"
                logger.warning(f"Regex parser insufficient ({regex_error}), trying LLM fallback...")
            else:
                logger.info(
                    f"No regex parser for {bank.value}/{statement_type.value}, "
                    f"using LLM fallback..."
                )
                # Extract raw text via pdfplumber directly
                if not raw_text:
                    try:
                        import pdfplumber
                        with pdfplumber.open(tmp_path) as pdf:
                            raw_text = "\n".join(
                                page.extract_text() or "" for page in pdf.pages
                            )
                    except Exception as e:
                        logger.warning(f"Failed to extract raw text: {e}")

            # Step 2: LLM fallback (works for any bank)
            if settings.llm_provider.lower() != "none" and raw_text:
                try:
                    from app.parsers.llm_parser import parse_with_llm_generic

                    llm_result = parse_with_llm_generic(raw_text, bank, statement_type)
                    if llm_result.success and llm_result.result:
                        txn_count = len(getattr(llm_result.result, "transactions", []))
                        logger.info(f"LLM fallback succeeded: {txn_count} transactions")
                        return {
                            "success": True,
                            "statement": llm_result.result,
                            "rawText": raw_text,
                            "parser": "llm",
                        }
                    else:
                        logger.warning(f"LLM fallback failed: {llm_result.error_message}")
                except Exception as e:
                    logger.warning(f"LLM fallback error: {e}")

            # Both failed
            if parser and not result.success:
                return {
                    "success": False,
                    "error": result.error_message,
                    "statement": getattr(result, "result", None),
                    "rawText": raw_text,
                    "parser": "regex",
                }

            return {
                "success": False,
                "error": f"No parser available for {bank.value}/{statement_type.value} "
                         f"and LLM fallback failed or is disabled",
                "rawText": raw_text,
                "parser": "none",
            }

        finally:
            Path(tmp_path).unlink(missing_ok=True)

    # ── Legacy entry points (backward compatible) ─────────────

    async def parse_hdfc_credit_card(
        self, file_content: bytes, filename: str
    ) -> CreditCardStatementSchema:
        """Parse HDFC credit card PDF. Legacy method — delegates to unified parser."""
        result = await self.parse_statement(
            file_content, filename, BankType.HDFC, StatementType.CREDIT_CARD
        )
        statement = result.get("statement")
        if statement is None:
            raise ParseException(result.get("error", "Parse failed"))
        return statement

    async def parse_hdfc_credit_card_debug(
        self, file_content: bytes, filename: str
    ) -> dict:
        """Parse with debug info. Legacy method — delegates to unified parser."""
        return await self.parse_statement(
            file_content, filename, BankType.HDFC, StatementType.CREDIT_CARD
        )

    async def parse_hdfc_savings(
        self, file_content: bytes, filename: str
    ) -> SavingsAccountStatementSchema:
        """Parse HDFC savings PDF. Legacy method — delegates to unified parser."""
        result = await self.parse_statement(
            file_content, filename, BankType.HDFC, StatementType.SAVINGS
        )
        statement = result.get("statement")
        if statement is None:
            raise ParseException(result.get("error", "Parse failed"))
        return statement

    # ── Utilities ─────────────────────────────────────────────

    def _validate_upload(self, file_content: bytes) -> None:
        """Validate uploaded file (size + PDF magic)."""
        if len(file_content) > settings.max_upload_size_bytes:
            raise ValueError(
                f"File too large. Max allowed is {settings.max_upload_size_mb}MB"
            )
        if not file_content[:4].startswith(PDF_MAGIC):
            raise ValueError("Uploaded file is not a valid PDF")

    @staticmethod
    def _save_temp_file(content: bytes, prefix: str = "upload-") -> str:
        """Save content to a temp file and return path."""
        tmp = tempfile.NamedTemporaryFile(
            prefix=prefix, suffix=".pdf", delete=False
        )
        tmp.write(content)
        tmp.close()
        return tmp.name

    @staticmethod
    def _load_parser_profile(filename: str) -> ParserProfile | None:
        """Attempt to load a YAML parser profile from the resources directory."""
        try:
            import yaml

            profile_path = Path(__file__).parent.parent / "resources" / filename
            if profile_path.exists():
                with open(profile_path) as f:
                    data = yaml.safe_load(f)
                    if data and "regions" in data:
                        return ParserProfile(regions=data["regions"])
        except Exception:
            pass
        return None
