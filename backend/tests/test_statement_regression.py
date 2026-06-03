import pytest

from tests.fixtures.statement_cases import PHASE0_CASES, assertable_phase0_cases, review_phase0_cases
from tests.helpers.statement_case_loader import (
    case_skip_reason,
    parse_statement_case,
    resolve_statement_corpus_root,
)


def test_phase0_manifest_keys_are_unique():
    keys = [case.key for case in PHASE0_CASES]
    assert len(keys) == len(set(keys))


def test_phase0_manifest_has_assertable_and_review_cases():
    assert assertable_phase0_cases()
    assert review_phase0_cases()


@pytest.fixture(scope="module")
def statement_corpus_root():
    root = resolve_statement_corpus_root()
    if root is None:
        pytest.skip("Statement corpus not found. Set FINANCE_TRACKER_STATEMENT_CORPUS_ROOT.")
    return root


@pytest.mark.parametrize("case", assertable_phase0_cases(), ids=lambda case: case.key)
def test_phase0_assertable_cases(statement_corpus_root, case):
    skip_reason = case_skip_reason(case, statement_corpus_root)
    if skip_reason:
        pytest.skip(skip_reason)

    snapshot = parse_statement_case(case, statement_corpus_root)

    assert snapshot["success"] is True, snapshot["error"]

    if case.expected_strategy is not None:
        assert snapshot["strategy"] == case.expected_strategy

    if case.minimum_transactions is not None:
        assert snapshot["transaction_count"] >= case.minimum_transactions

    if case.expected_opening_balance is not None:
        assert snapshot["opening_balance"] == case.expected_opening_balance

    if case.expected_closing_balance is not None:
        assert snapshot["closing_balance"] == case.expected_closing_balance