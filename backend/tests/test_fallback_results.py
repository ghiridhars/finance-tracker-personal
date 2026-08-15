from app.parsing.fallbacks import build_parse_failure_result, build_parse_success_result
from app.parsing.fallbacks.review import ReviewFallbackOutcome


class _StubValidation:
    def __init__(self, *, trusted: bool):
        self.trusted = trusted

    def to_dict(self):
        return {"trusted": self.trusted, "summary": {"status": "trusted" if self.trusted else "review_required"}}


def test_build_parse_success_result_serializes_review_fallback():
    validation = _StubValidation(trusted=False)
    review_fallback = ReviewFallbackOutcome(
        type="review",
        action="manual_review",
        confidence="low",
        reason_codes=("validate.balance.reconciliation_failed",),
        message="Manual review required: validate.balance.reconciliation_failed",
    )

    result = build_parse_success_result(
        statement={"id": 1},
        raw_text="raw text",
        parser_name="llm",
        strategy="llm",
        validation=validation,
        review_fallback=review_fallback,
    )

    assert result["success"] is True
    assert result["parser"] == "llm"
    assert result["trusted"] is False
    assert result["review_fallback"] == {
        "type": "review",
        "action": "manual_review",
        "confidence": "low",
        "reason_codes": ["validate.balance.reconciliation_failed"],
        "message": "Manual review required: validate.balance.reconciliation_failed",
        "mismatched_indices": [],
        "valid_indices": [],
    }


def test_build_parse_failure_result_uses_generic_owner_when_llm_not_attempted():
    result = build_parse_failure_result(
        message="Generic parser failed: no rows",
        raw_text="raw text",
        generic_error="no rows",
        llm_status="skipped_provider_none",
        llm_error="LLM fallback skipped because llm_provider is set to none.",
    )

    assert result.stage == "generic_parse"
    assert result.code == "parser.generic_parse_failed"
    assert result.payload["error"] == "Generic parser failed: no rows"
    assert result.payload["llm_status"] == "skipped_provider_none"


def test_build_parse_failure_result_uses_llm_owner_when_llm_attempted():
    result = build_parse_failure_result(
        message="Generic parser failed: no rows. LLM fallback failed: model unavailable",
        raw_text="raw text",
        generic_error="no rows",
        llm_status="attempted",
        llm_error="model unavailable",
    )

    assert result.stage == "llm_fallback"
    assert result.code == "parser.llm_fallback_failed"
    assert result.payload["parser"] == "none"
    assert result.payload["llm_error"] == "model unavailable"