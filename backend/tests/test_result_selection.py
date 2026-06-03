from types import SimpleNamespace

from app.parsers.base_parser import ParseResult
from app.parsing.result_selection import result_transaction_count, select_best_result


def _result_with_count(count: int, *, strategy: str) -> ParseResult:
    return ParseResult.ok(
        SimpleNamespace(transactions=[object() for _ in range(count)]),
        strategy=strategy,
    )


class TestResultSelection:
    def test_result_transaction_count_ignores_failed_or_missing_results(self):
        assert result_transaction_count(None) == 0
        assert result_transaction_count(ParseResult.failure("nope")) == 0
        assert result_transaction_count(ParseResult.ok(SimpleNamespace())) == 0

    def test_select_best_result_prefers_highest_transaction_count(self):
        selected = select_best_result(
            [
                _result_with_count(1, strategy="single_line"),
                _result_with_count(3, strategy="multiline"),
                _result_with_count(2, strategy="table"),
            ]
        )

        assert selected is not None
        assert selected.strategy == "multiline"

    def test_select_best_result_preserves_first_tie(self):
        first = _result_with_count(2, strategy="table")
        second = _result_with_count(2, strategy="multiline")

        selected = select_best_result([first, second])

        assert selected is first