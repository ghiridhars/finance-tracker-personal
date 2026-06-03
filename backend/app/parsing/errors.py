STAGE_VALIDATE_PDF = "validate_pdf"
STAGE_VALIDATE_STATEMENT = "validate_statement"
STAGE_SAVE_TEMP_FILE = "save_temp_file"
STAGE_EXTRACT_RAW_TEXT = "extract_raw_text"
STAGE_GENERIC_PARSE = "generic_parse"
STAGE_LLM_FALLBACK = "llm_fallback"
STAGE_REVIEW_FALLBACK = "review_fallback"
STAGE_CLEANUP_TEMP_FILE = "cleanup_temp_file"

ERROR_INVALID_PDF = "parser.invalid_pdf"
ERROR_SAVE_TEMP_FILE = "parser.save_temp_file_failed"
ERROR_GENERIC_PARSE = "parser.generic_parse_failed"
ERROR_LLM_FALLBACK = "parser.llm_fallback_failed"

_OWNER_BY_STAGE = {
    STAGE_VALIDATE_PDF: "app.parsing.service.parser_service",
    STAGE_VALIDATE_STATEMENT: "app.parsing.validation",
    STAGE_SAVE_TEMP_FILE: "app.parsing.service.parser_service",
    STAGE_EXTRACT_RAW_TEXT: "app.parsers.generic_pdf_parser",
    STAGE_GENERIC_PARSE: "app.parsers.generic_pdf_parser",
    STAGE_LLM_FALLBACK: "app.parsers.llm_parser",
    STAGE_REVIEW_FALLBACK: "app.parsing.fallbacks.review",
    STAGE_CLEANUP_TEMP_FILE: "app.parsing.service.parser_service",
}


def owner_for_stage(stage: str) -> str:
    return _OWNER_BY_STAGE.get(stage, "app.parsing.engine")