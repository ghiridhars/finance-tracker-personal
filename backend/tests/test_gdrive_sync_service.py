from types import SimpleNamespace

import pytest


class _FakeDbSession:
    def __init__(self):
        self.commits = 0
        self.rollbacks = 0

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


@pytest.mark.asyncio
async def test_failed_parse_detail_includes_parse_failure_summary(tmp_path, monkeypatch):
    from app.services import gdrive_sync_service as svc

    monkeypatch.setattr(svc.settings, "data_dir", str(tmp_path), raising=False)

    class FakeFilesResource:
        def get_media(self, fileId):
            return {"fileId": fileId}

    class FakeDriveService:
        def files(self):
            return FakeFilesResource()

    class FakeDownloader:
        def __init__(self, buffer, request):
            self._buffer = buffer
            self._done = False

        def next_chunk(self):
            if not self._done:
                self._buffer.write(b"%PDF-1.4 test")
                self._done = True
            return None, True

    class FakeParserService:
        async def parse_statement(
            self,
            file_content,
            filename,
            bank,
            statement_type,
            password=None,
        ):
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

    monkeypatch.setattr(svc, "_get_drive_service", lambda: FakeDriveService())
    monkeypatch.setattr(svc, "MediaIoBaseDownload", FakeDownloader)
    monkeypatch.setattr("app.parsing.service.ParserService", FakeParserService)

    recorded_failures: list[dict] = []
    monkeypatch.setattr(
        "app.services.statement_audit_service.StatementAuditService.record",
        lambda *args, **kwargs: recorded_failures.append(kwargs),
    )

    result = await svc.download_and_import(
        db=_FakeDbSession(),
        files=[
            {
                "filepath": "drive-file-1",
                "filename": "statement.pdf",
                "bank": "BOB",
                "type": "SAVINGS",
            }
        ],
        job_id="job-1",
    )

    assert result["processed"] == 0
    assert result["failed"] == 1
    assert result["details"][0]["status"] == "failed"
    assert result["details"][0]["error"] == (
        "Generic parser failed: no rows "
        "(stage: llm_fallback, code: parser.llm_fallback_failed)"
    )
    assert result["details"][0]["parse_failure"] == {
        "stage": "llm_fallback",
        "code": "parser.llm_fallback_failed",
        "owner": "app.parsers.llm_parser",
        "message": "Generic parser failed: no rows. LLM fallback failed: model unavailable",
        "parser": "none",
        "generic_error": "no rows",
        "llm_status": "attempted",
        "llm_error": "model unavailable",
    }
    assert recorded_failures[0]["error_message"] == result["details"][0]["error"]