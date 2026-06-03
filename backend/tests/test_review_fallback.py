from app.parsing.fallbacks import build_review_fallback
from app.parsing.models import ValidationReport


class TestReviewFallback:
    def test_returns_none_for_trusted_validation(self):
        report = ValidationReport()
        report.add_check(name="transaction_count", status="passed", message="1 transaction")

        outcome = build_review_fallback(report)

        assert outcome is None

    def test_builds_manual_review_outcome_for_untrusted_validation(self):
        report = ValidationReport()
        report.add_check(
            name="balance_reconciliation",
            status="failed",
            code="validate.balance.reconciliation_failed",
            message="boom",
        )

        outcome = build_review_fallback(report)

        assert outcome is not None
        assert outcome.type == "review"
        assert outcome.action == "manual_review"
        assert outcome.confidence == "low"
        assert outcome.reason_codes == ("validate.balance.reconciliation_failed",)
        assert outcome.message == "Manual review required: validate.balance.reconciliation_failed"