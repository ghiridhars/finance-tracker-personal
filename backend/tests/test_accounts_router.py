import json
from types import SimpleNamespace

import pytest

from app.routers.accounts import _audit_to_dict, list_statements


def test_audit_to_dict_excludes_trace_by_default():
    audit = SimpleNamespace(
        id=1,
        file_name="statement.pdf",
        bank_name="BOB",
        statement_type="SAVINGS",
        bank_account_id=2,
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        transaction_count=3,
        parser_strategy="multiline",
        status="SUCCESS",
        error_message=None,
        source="upload",
        imported_at=None,
        parse_trace=json.dumps({"events": [{"stage": "generic_parse"}]}),
    )

    payload = _audit_to_dict(audit)

    assert "parse_trace" not in payload


def test_audit_to_dict_includes_deserialized_trace_when_requested():
    audit = SimpleNamespace(
        id=1,
        file_name="statement.pdf",
        bank_name="BOB",
        statement_type="SAVINGS",
        bank_account_id=2,
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        transaction_count=3,
        parser_strategy="multiline",
        status="SUCCESS",
        error_message=None,
        source="upload",
        imported_at=None,
        parse_trace=json.dumps({"events": [{"stage": "generic_parse"}]}),
    )

    payload = _audit_to_dict(audit, include_trace=True)

    assert payload["parse_trace"] == {"events": [{"stage": "generic_parse"}]}


def test_audit_to_dict_surfaces_trusted_state_from_trace():
    audit = SimpleNamespace(
        id=1,
        file_name="statement.pdf",
        bank_name="BOB",
        statement_type="SAVINGS",
        bank_account_id=2,
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        transaction_count=3,
        parser_strategy="multiline",
        status="SUCCESS",
        error_message=None,
        source="upload",
        imported_at=None,
        parse_trace=json.dumps(
            {
                "events": [{"stage": "generic_parse"}],
                "validation": {
                    "trusted": False,
                    "summary": {
                        "status": "review_required",
                        "confidence": "low",
                        "check_counts": {"passed": 0, "failed": 1, "skipped": 0},
                        "failed_codes": ["validate.balance.reconciliation_failed"],
                    },
                    "checks": [
                        {
                            "name": "balance_reconciliation",
                            "status": "failed",
                            "code": "validate.balance.reconciliation_failed",
                        }
                    ],
                },
            }
        ),
    )

    payload = _audit_to_dict(audit)

    assert payload["trusted"] is False
    assert payload["validation_failed_codes"] == ["validate.balance.reconciliation_failed"]
    assert payload["validation_summary"]["status"] == "review_required"
    assert payload["validation_summary"]["confidence"] == "low"


def test_audit_to_dict_derives_validation_summary_for_legacy_trace():
    audit = SimpleNamespace(
        id=1,
        file_name="statement.pdf",
        bank_name="BOB",
        statement_type="SAVINGS",
        bank_account_id=2,
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        transaction_count=3,
        parser_strategy="multiline",
        status="SUCCESS",
        error_message=None,
        source="upload",
        imported_at=None,
        parse_trace=json.dumps(
            {
                "events": [{"stage": "generic_parse"}],
                "validation": {
                    "trusted": True,
                    "checks": [
                        {
                            "name": "transaction_count",
                            "status": "passed",
                        },
                        {
                            "name": "date_range",
                            "status": "skipped",
                        },
                    ],
                },
            }
        ),
    )

    payload = _audit_to_dict(audit)

    assert payload["validation_summary"]["status"] == "trusted"
    assert payload["validation_summary"]["confidence"] == "medium"
    assert payload["validation_summary"]["check_counts"] == {"passed": 1, "failed": 0, "skipped": 1}


def test_audit_to_dict_surfaces_parse_failure_summary_for_failed_audit():
    audit = SimpleNamespace(
        id=2,
        file_name="broken.pdf",
        bank_name="BOB",
        statement_type="SAVINGS",
        bank_account_id=None,
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        transaction_count=0,
        parser_strategy="none",
        status="FAILED",
        error_message="Generic parser failed: no rows (stage: generic_parse, code: parser.generic_parse_failed)",
        source="upload",
        imported_at=None,
        parse_trace=json.dumps(
            {
                "failure": {
                    "stage": "generic_parse",
                    "code": "parser.generic_parse_failed",
                    "owner": "app.parsers.generic_pdf_parser",
                    "message": "Generic parser failed: no rows",
                }
            }
        ),
    )

    payload = _audit_to_dict(audit)

    assert payload["status"] == "FAILED"
    assert payload["error_message"] == audit.error_message
    assert payload["parse_failure"] == {
        "stage": "generic_parse",
        "code": "parser.generic_parse_failed",
        "owner": "app.parsers.generic_pdf_parser",
        "message": "Generic parser failed: no rows",
        "parser": "none",
    }


def test_list_statements_passes_status_filter_to_service(monkeypatch):
    captured: dict[str, object] = {}

    def fake_list_statements(db, **kwargs):
        captured.update(kwargs)
        return [], 0

    monkeypatch.setattr(
        "app.routers.accounts.StatementManagementService.list_statements",
        fake_list_statements,
    )

    response = list_statements(status="FAILED", limit=10, offset=5, db=object())

    assert response["items"] == []
    assert response["total"] == 0
    assert captured["status"] == "FAILED"
    assert captured["limit"] == 10
    assert captured["offset"] == 5


def test_list_statements_rejects_invalid_status():
    with pytest.raises(Exception) as exc_info:
        list_statements(status="BROKEN", db=object())

    assert "status must be SUCCESS or FAILED" in str(exc_info.value)