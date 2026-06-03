from app.parsing.extraction.statement_metadata import extract_statement_metadata


class TestStatementMetadataExtraction:
    def test_extracts_period_and_account_number(self):
        metadata = extract_statement_metadata(
            "Account Number: 1234567890123\nStatement from 01/01/2024 to 31/01/2024"
        )

        assert metadata.period_from == "01/01/2024"
        assert metadata.period_to == "31/01/2024"
        assert metadata.account_number == "1234567890123"
        assert metadata.card_number is None

    def test_to_dict_omits_missing_fields(self):
        metadata = extract_statement_metadata("Card Number: 4632 02XX XXXX 4418")

        assert metadata.to_dict() == {"card_number": "4632 02XX XXXX 4418"}

    def test_extracts_period_with_keyword(self):
        metadata = extract_statement_metadata("Period: 01-01-2024 to 31-01-2024")

        assert metadata.to_dict() == {
            "period_from": "01-01-2024",
            "period_to": "31-01-2024",
        }

    def test_extracts_account_number_from_alternate_prefix(self):
        metadata = extract_statement_metadata("A/C No. 9876 5432 1098")

        assert metadata.account_number is not None

    def test_ignores_placeholder_account_number_words(self):
        metadata = extract_statement_metadata("Account Number: NOMINEE")

        assert "account_number" not in metadata.to_dict()

    def test_extracts_digits_before_trailing_words(self):
        metadata = extract_statement_metadata(
            "A/C No. 0557201810135605460437 NOMINEE REGISTERED"
        )

        assert metadata.account_number == "0557201810135605460437"

    def test_ignores_joint_placeholder_account_number(self):
        metadata = extract_statement_metadata("Account No: Joint")

        assert "account_number" not in metadata.to_dict()

    def test_extracts_contiguous_masked_card_number(self):
        metadata = extract_statement_metadata("463202XXXXXX4418")

        assert metadata.card_number == "463202XXXXXX4418"

    def test_returns_empty_dict_for_unmatched_text(self):
        metadata = extract_statement_metadata("Some random text without any recognizable patterns")

        assert metadata.to_dict() == {}