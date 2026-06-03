from app.models.enums import BankType, StatementType
from app.parsing.classifiers import classify_template
from app.parsing.profiles import StrategyProfile


class TestTemplateClassifier:
    def test_matches_registered_profile(self):
        classification = classify_template(
            "Statement of transactions in Savings Account\nWITHDRAWAL (DR)",
            StatementType.SAVINGS,
        )

        assert classification is not None
        assert classification.profile_id == "bob_savings_v1"
        assert classification.score == 1
        assert classification.bank_constrained is False

    def test_respects_declared_bank_constraint(self):
        classification = classify_template(
            "HDFC BANK CREDIT CARD STATEMENT",
            StatementType.CREDIT_CARD,
            bank=BankType.BOB,
        )

        assert classification is None

    def test_prefers_higher_scoring_profile_when_multiple_match(self):
        profiles = (
            StrategyProfile(
                id="low_score",
                bank=BankType.OTHER,
                statement_type=StatementType.SAVINGS,
                required_text=("statement",),
                preferred_order=("table",),
            ),
            StrategyProfile(
                id="high_score",
                bank=BankType.OTHER,
                statement_type=StatementType.SAVINGS,
                required_text=("statement", "savings"),
                preferred_order=("multiline",),
            ),
        )

        classification = classify_template(
            "Generic savings statement",
            StatementType.SAVINGS,
            profiles=profiles,
        )

        assert classification is not None
        assert classification.profile_id == "high_score"
        assert classification.score == 2