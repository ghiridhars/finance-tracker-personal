import json
from io import BytesIO

import pytest
from starlette.datastructures import Headers, UploadFile

from app.routers import upload as upload_router


class _FakeDbSession:
    def __init__(self):
        self.commits = 0

    def commit(self):
        self.commits += 1


@pytest.mark.asyncio
async def test_upload_statement_failure_returns_parse_failure_summary(monkeypatch):
    async def fake_parse_statement(content, filename, bank, statement_type, password=None):
        return {
            "success": False,
            "error": "Generic parser failed: no rows",
            "parser": "none",
            "generic_error": "no rows",
            "llm_status": "attempted",
            "llm_error": "model unavailable",
            "trace": {
                "failure": {
                    "stage": "llm_fallback",
                    "code": "parser.llm_fallback_failed",
                    "owner": "app.parsers.llm_parser",
                    "message": "Generic parser failed: no rows. LLM fallback failed: model unavailable",
                }
            },
        }

    monkeypatch.setattr(upload_router.parser_service, "parse_statement", fake_parse_statement)

    recorded_audits: list[dict] = []
    monkeypatch.setattr(
        "app.services.statement_audit_service.StatementAuditService.record",
        lambda *args, **kwargs: recorded_audits.append(kwargs),
    )

    response = await upload_router.upload_statement_v2(
        file=UploadFile(
            filename="statement.pdf",
            file=BytesIO(b"%PDF-1.4 dummy"),
            headers=Headers({"content-type": "application/pdf"}),
        ),
        bank="BOB",
        type="SAVINGS",
        save=False,
        password=None,
        db=_FakeDbSession(),
    )

    assert response.status_code == 400
    payload = json.loads(response.body.decode())
    assert payload["detail"] == (
        "Generic parser failed: no rows "
        "(stage: llm_fallback, code: parser.llm_fallback_failed)"
    )
    assert payload["parse_failure"] == {
        "stage": "llm_fallback",
        "code": "parser.llm_fallback_failed",
        "owner": "app.parsers.llm_parser",
        "message": "Generic parser failed: no rows. LLM fallback failed: model unavailable",
        "parser": "none",
        "generic_error": "no rows",
        "llm_status": "attempted",
        "llm_error": "model unavailable",
    }
    assert recorded_audits[0]["error_message"] == payload["detail"]