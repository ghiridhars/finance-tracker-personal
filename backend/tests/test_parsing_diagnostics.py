from app.parsing.diagnostics import annotate_parse_failure_message, extract_parse_failure


def test_extract_parse_failure_reads_trace_failure_payload():
    result = {
        "success": False,
        "error": "Generic parser failed: no rows",
        "parser": "none",
        "generic_error": "no rows",
        "llm_status": "skipped_provider_none",
        "llm_error": "LLM fallback skipped because llm_provider is set to none.",
        "trace": {
            "failure": {
                "stage": "generic_parse",
                "code": "parser.generic_parse_failed",
                "owner": "app.parsers.generic_pdf_parser",
                "message": "Generic parser failed: no rows",
            }
        },
    }

    failure = extract_parse_failure(result)

    assert failure == {
        "stage": "generic_parse",
        "code": "parser.generic_parse_failed",
        "owner": "app.parsers.generic_pdf_parser",
        "message": "Generic parser failed: no rows",
        "parser": "none",
        "generic_error": "no rows",
        "llm_status": "skipped_provider_none",
        "llm_error": "LLM fallback skipped because llm_provider is set to none.",
    }


def test_extract_parse_failure_infers_stage_without_trace_failure():
    result = {
        "success": False,
        "error": "Generic parser failed: no rows. LLM fallback failed: model unavailable",
        "parser": "none",
        "generic_error": "no rows",
        "llm_status": "attempted",
        "llm_error": "model unavailable",
    }

    failure = extract_parse_failure(result)

    assert failure is not None
    assert failure["stage"] == "llm_fallback"
    assert failure["code"] == "parser.llm_fallback_failed"
    assert failure["llm_error"] == "model unavailable"


def test_annotate_parse_failure_message_appends_stage_and_code_once():
    failure = {
        "stage": "llm_fallback",
        "code": "parser.llm_fallback_failed",
    }

    message = annotate_parse_failure_message(
        "Generic parser failed: no rows. LLM fallback failed: model unavailable",
        failure,
    )

    assert message == (
        "Generic parser failed: no rows. LLM fallback failed: model unavailable "
        "(stage: llm_fallback, code: parser.llm_fallback_failed)"
    )
    assert annotate_parse_failure_message(message, failure) == message