"""
Unit tests for local directory sync — file utilities and service functions.

Tests file type inference, directory listing, state tracking,
path configuration, and edge cases.
"""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.parsers.base_parser import ParseException
from app.utils.file_utils import infer_file_type, is_supported_file, is_csv_file


# ── infer_file_type ─────────────────────────────────────────────


class TestInferFileType:
    """Tests for bank and statement type inference from filenames."""

    def test_hdfc_credit_card_pdf(self):
        bank, stype = infer_file_type("HDFC_credit_card_jan2025.pdf")
        assert bank == "HDFC"
        assert stype == "CREDIT_CARD"

    def test_icici_savings_csv(self):
        bank, stype = infer_file_type("ICICI_savings_2024.csv")
        assert bank == "ICICI"
        assert stype == "SAVINGS"

    def test_sbi_cc_shorthand(self):
        bank, stype = infer_file_type("SBI_cc_march.pdf")
        assert bank == "SBI"
        assert stype == "CREDIT_CARD"

    def test_axis_creditcard_no_underscore(self):
        bank, stype = infer_file_type("AXIS_creditcard_2025.pdf")
        assert bank == "AXIS"
        assert stype == "CREDIT_CARD"

    def test_unknown_bank_defaults_to_other(self):
        bank, stype = infer_file_type("statement_jan2025.pdf")
        assert bank == "OTHER"

    def test_pdf_defaults_to_credit_card(self):
        """Unrecognized PDF defaults to CREDIT_CARD type."""
        bank, stype = infer_file_type("some_file.pdf")
        assert stype == "CREDIT_CARD"

    def test_csv_defaults_to_savings(self):
        """Unrecognized CSV defaults to SAVINGS type."""
        bank, stype = infer_file_type("some_file.csv")
        assert stype == "SAVINGS"

    def test_bank_detected_from_parent_folder(self):
        """Detect bank from parent folder when filename doesn't match."""
        bank, stype = infer_file_type("jan2025.pdf", relative_path="HDFC/jan2025.pdf")
        assert bank == "HDFC"

    def test_nested_folder_bank_detection(self):
        bank, stype = infer_file_type(
            "statement.pdf", relative_path="statements/ICICI/2025/statement.pdf"
        )
        assert bank == "ICICI"

    def test_type_detected_from_folder(self):
        """Detect statement type from folder name."""
        bank, stype = infer_file_type(
            "jan2025.pdf", relative_path="HDFC/credit_card/jan2025.pdf"
        )
        assert stype == "CREDIT_CARD"

    def test_savings_folder_hint(self):
        bank, stype = infer_file_type(
            "jan2025.csv", relative_path="savings/jan2025.csv"
        )
        assert stype == "SAVINGS"

    def test_case_insensitive(self):
        bank, stype = infer_file_type("hdfc_Credit_Card_jan.pdf")
        assert bank == "HDFC"
        assert stype == "CREDIT_CARD"

    def test_spaces_in_filename(self):
        bank, stype = infer_file_type("HDFC credit card jan.pdf")
        assert bank == "HDFC"
        assert stype == "CREDIT_CARD"

    def test_kotak_bank(self):
        bank, stype = infer_file_type("KOTAK_savings_dec.csv")
        assert bank == "KOTAK"
        assert stype == "SAVINGS"

    def test_empty_relative_path(self):
        bank, stype = infer_file_type("unknown_file.pdf", relative_path="")
        assert bank == "OTHER"

    def test_xlsx_is_savings(self):
        bank, stype = infer_file_type("transactions.xlsx")
        assert stype == "SAVINGS"

    def test_filename_takes_priority_over_folder(self):
        """When filename explicitly contains bank name, prefer it over folder."""
        bank, stype = infer_file_type(
            "SBI_savings.csv", relative_path="HDFC/SBI_savings.csv"
        )
        assert bank == "SBI"


# ── is_supported_file ───────────────────────────────────────────


class TestIsSupportedFile:
    def test_pdf(self):
        assert is_supported_file("statement.pdf") is True

    def test_csv(self):
        assert is_supported_file("data.csv") is True

    def test_xlsx(self):
        assert is_supported_file("sheet.xlsx") is True

    def test_xls(self):
        assert is_supported_file("old.xls") is True

    def test_txt(self):
        assert is_supported_file("raw.txt") is True

    def test_tsv(self):
        assert is_supported_file("tab.tsv") is True

    def test_jpg_not_supported(self):
        assert is_supported_file("photo.jpg") is False

    def test_docx_not_supported(self):
        assert is_supported_file("doc.docx") is False

    def test_no_extension(self):
        assert is_supported_file("README") is False

    def test_case_insensitive(self):
        assert is_supported_file("DATA.CSV") is True
        assert is_supported_file("Report.PDF") is True


# ── is_csv_file ─────────────────────────────────────────────────


class TestIsCsvFile:
    def test_csv(self):
        assert is_csv_file("data.csv") is True

    def test_xlsx(self):
        assert is_csv_file("data.xlsx") is True

    def test_pdf_is_not_csv(self):
        assert is_csv_file("statement.pdf") is False

    def test_txt_is_csv(self):
        assert is_csv_file("raw.txt") is True


# ── list_local_files (with temp directory) ──────────────────────


class TestListLocalFiles:
    """Tests file listing with a real temp directory."""

    @pytest.fixture(autouse=True)
    def _allow_tmp(self, tmp_path, monkeypatch):
        """Allow tmp_path in path validation for tests."""
        from app.services import local_sync_service as svc
        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [tmp_path])

    def test_lists_supported_files(self, tmp_path):
        """Should discover PDF and CSV files recursively."""
        from app.services import local_sync_service as svc

        # Create files
        (tmp_path / "hdfc_cc_jan.pdf").write_bytes(b"dummy pdf")
        (tmp_path / "icici_savings.csv").write_text("header\nrow1")
        (tmp_path / "readme.txt").write_text("notes")
        (tmp_path / "photo.jpg").write_bytes(b"not a statement")

        files = svc.list_local_files(str(tmp_path))

        filenames = {f["filename"] for f in files}
        assert "hdfc_cc_jan.pdf" in filenames
        assert "icici_savings.csv" in filenames
        assert "readme.txt" in filenames  # .txt is supported
        assert "photo.jpg" not in filenames

    def test_recursive_scan(self, tmp_path):
        """Should find files in subdirectories."""
        from app.services import local_sync_service as svc

        subdir = tmp_path / "HDFC" / "2025"
        subdir.mkdir(parents=True)
        (subdir / "jan.pdf").write_bytes(b"dummy")
        (tmp_path / "root.csv").write_text("data")

        files = svc.list_local_files(str(tmp_path))
        assert len(files) == 2

        # Verify relative paths
        pdf_file = next(f for f in files if f["filename"] == "jan.pdf")
        assert "HDFC" in pdf_file["relative_path"]

    def test_infers_bank_from_subfolder(self, tmp_path):
        """Bank should be inferred from parent folder name."""
        from app.services import local_sync_service as svc

        subdir = tmp_path / "ICICI"
        subdir.mkdir()
        (subdir / "statement.pdf").write_bytes(b"dummy")

        files = svc.list_local_files(str(tmp_path))
        assert files[0]["inferred_bank"] == "ICICI"

    def test_empty_directory(self, tmp_path):
        """Empty directory should return empty list."""
        from app.services import local_sync_service as svc

        files = svc.list_local_files(str(tmp_path))
        assert files == []

    def test_returns_file_metadata(self, tmp_path):
        """Each file entry should include all expected metadata fields."""
        from app.services import local_sync_service as svc

        (tmp_path / "test.pdf").write_bytes(b"x" * 100)

        files = svc.list_local_files(str(tmp_path))
        assert len(files) == 1

        f = files[0]
        assert "filepath" in f
        assert "relative_path" in f
        assert "filename" in f
        assert "size" in f
        assert f["size"] == 100
        assert "modified_time" in f
        assert "inferred_bank" in f
        assert "inferred_type" in f
        assert "already_processed" in f
        assert "file_key" in f

    def test_invalid_path_raises(self):
        """Non-existent path should raise ValueError."""
        from app.services import local_sync_service as svc

        with pytest.raises(ValueError, match="not a directory"):
            svc.list_local_files("/nonexistent/path/that/does/not/exist")

    def test_sorted_by_modified_time(self, tmp_path):
        """Files should be sorted newest-first by modification time."""
        import time
        from app.services import local_sync_service as svc

        (tmp_path / "old.pdf").write_bytes(b"old")
        time.sleep(0.05)
        (tmp_path / "new.pdf").write_bytes(b"new")

        files = svc.list_local_files(str(tmp_path))
        assert files[0]["filename"] == "new.pdf"
        assert files[1]["filename"] == "old.pdf"


# ── State tracking ──────────────────────────────────────────────


class TestSyncState:
    """Tests for sync state persistence and reset."""

    @pytest.fixture(autouse=True)
    def _allow_tmp(self, tmp_path, monkeypatch):
        """Allow tmp_path in path validation for tests."""
        from app.services import local_sync_service as svc
        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [tmp_path])

    def test_configure_path_valid(self, tmp_path):
        """Valid path should be accepted and persisted."""
        from app.services import local_sync_service as svc

        (tmp_path / "test.pdf").write_bytes(b"dummy")

        result = svc.configure_path(str(tmp_path))
        assert result["success"] is True
        assert result["file_count"] == 1

    def test_configure_path_nonexistent(self):
        """Non-existent path should raise ValueError."""
        from app.services import local_sync_service as svc

        with pytest.raises(ValueError, match="does not exist"):
            svc.configure_path("/definitely/not/a/real/path")

    def test_configure_path_file_not_dir(self, tmp_path):
        """A file (not directory) should raise ValueError."""
        from app.services import local_sync_service as svc

        f = tmp_path / "file.txt"
        f.write_text("hi")

        with pytest.raises(ValueError, match="not a directory"):
            svc.configure_path(str(f))

    def test_reset_all(self, tmp_path, monkeypatch):
        """reset_sync_state with no args should clear all processed files."""
        from app.services import local_sync_service as svc

        # Write fake state
        state_file = tmp_path / ".local_sync_state.json"
        state = {
            "processed_files": {"abc123": {"filepath": "/a"}, "def456": {"filepath": "/b"}},
            "last_scan": "2025-01-01T00:00:00Z",
        }
        state_file.write_text(json.dumps(state))

        # Monkeypatch the state file path
        monkeypatch.setattr(svc, "_SYNC_STATE_FILE", state_file)

        result = svc.reset_sync_state()
        assert result["reset_count"] == 2

        # Verify state file is cleared
        reloaded = json.loads(state_file.read_text())
        assert len(reloaded["processed_files"]) == 0

    def test_get_sync_status(self, monkeypatch):
        """get_sync_status should return structured status info."""
        from app.services import local_sync_service as svc

        # Monkeypatch to return no configured path
        monkeypatch.setattr(svc, "get_configured_path", lambda: None)
        monkeypatch.setattr(svc, "_load_sync_state", lambda: {"processed_files": {}, "last_scan": None})

        status = svc.get_sync_status()
        assert status["configured_path"] is None
        assert status["path_exists"] is False
        assert status["processed_file_count"] == 0


# ── Path traversal & security tests ──────────────────────────────


class TestPathSecurity:
    """Tests for path validation and traversal prevention."""

    def test_path_outside_allowed_roots_rejected(self, tmp_path, monkeypatch):
        """Paths outside allowed roots should raise ValueError."""
        from app.services import local_sync_service as svc

        allowed = tmp_path / "allowed"
        allowed.mkdir()
        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [allowed])

        outside = tmp_path / "outside"
        outside.mkdir()

        with pytest.raises(ValueError, match="outside allowed directories"):
            svc.configure_path(str(outside))

    def test_path_inside_allowed_roots_accepted(self, tmp_path, monkeypatch):
        """Paths inside allowed roots should work fine."""
        from app.services import local_sync_service as svc

        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [tmp_path])
        monkeypatch.setattr(svc, "_PATH_CONFIG_FILE", tmp_path / ".cfg.json")

        sub = tmp_path / "statements"
        sub.mkdir()
        result = svc.configure_path(str(sub))
        assert result["success"] is True

    def test_list_files_outside_allowed_rejected(self, tmp_path, monkeypatch):
        """list_local_files should reject paths outside allowed roots."""
        from app.services import local_sync_service as svc

        allowed = tmp_path / "allowed"
        allowed.mkdir()
        outside = tmp_path / "outside"
        outside.mkdir()
        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [allowed])

        with pytest.raises(ValueError, match="outside allowed directories"):
            svc.list_local_files(str(outside))


# ── Concurrent scan guard tests ──────────────────────────────────


class TestConcurrencyGuard:
    """Tests for the single-active-scan guard."""

    def test_has_running_scan_false_when_empty(self):
        """has_running_scan should return False when no jobs exist."""
        from app.services import local_sync_service as svc

        svc._jobs.clear()
        assert svc.has_running_scan() is False

    def test_has_running_scan_true_when_running(self):
        """has_running_scan should return True when a job is running."""
        from app.services import local_sync_service as svc

        svc._jobs.clear()
        svc._jobs["test-job"] = {"status": "running"}
        assert svc.has_running_scan() is True
        svc._jobs.clear()

    def test_has_running_scan_false_when_completed(self):
        """has_running_scan should return False when all jobs are completed."""
        from app.services import local_sync_service as svc

        svc._jobs.clear()
        svc._jobs["test-job"] = {"status": "completed"}
        assert svc.has_running_scan() is False
        svc._jobs.clear()


class _FakeDbSession:
    def rollback(self):
        return None

    def commit(self):
        return None


class TestScanAndImportPasswords:
    @pytest.fixture(autouse=True)
    def _allow_tmp(self, tmp_path, monkeypatch):
        from app.services import local_sync_service as svc

        monkeypatch.setattr(svc, "_get_allowed_roots", lambda: [tmp_path])
        monkeypatch.setattr(svc, "get_configured_path", lambda: str(tmp_path))
        monkeypatch.setattr(svc, "_SYNC_STATE_FILE", tmp_path / ".local_sync_state.json")
        svc._jobs.clear()

    @pytest.mark.asyncio
    async def test_retries_multiple_password_candidates_until_success(
        self, tmp_path, monkeypatch
    ):
        from app.services import local_sync_service as svc

        filepath = tmp_path / "bob-statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        attempts: list[str | None] = []
        statement = SimpleNamespace(
            account_number="1234567890",
            account_holder_name="Bob",
            transactions=[SimpleNamespace()],
        )

        class FakeParserService:
            async def parse_statement(
                self,
                file_content,
                filename,
                bank,
                statement_type,
                password=None,
            ):
                attempts.append(password)
                if password != "correct-password":
                    raise ParseException("Incorrect PDF password.")
                return {
                    "success": True,
                    "statement": statement,
                    "parser": "generic",
                    "strategy": "table",
                }

        monkeypatch.setattr("app.services.parser_service.ParserService", FakeParserService)
        monkeypatch.setattr(
            "app.services.account_resolution_service.AccountResolutionService.resolve_or_create",
            lambda *args, **kwargs: SimpleNamespace(id=1),
        )

        saved_statements: list[dict] = []
        monkeypatch.setattr(
            "app.services.statement_audit_service.StatementAuditService.save_statement",
            lambda *args, **kwargs: saved_statements.append(kwargs),
        )

        result = await svc.scan_and_import(
            db=_FakeDbSession(),
            files=[
                {
                    "filepath": str(filepath),
                    "bank": "BOB",
                    "type": "SAVINGS",
                }
            ],
            bank_passwords={"BOB": ["wrong-password", "correct-password"]},
        )

        assert attempts == ["wrong-password", "correct-password"]
        assert result["processed"] == 1
        assert result["failed"] == 0
        assert result["details"][0]["status"] == "success"
        assert len(saved_statements) == 1

    @pytest.mark.asyncio
    async def test_reports_clear_error_when_all_password_candidates_fail(
        self, tmp_path, monkeypatch
    ):
        from app.services import local_sync_service as svc

        filepath = tmp_path / "bob-statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        attempts: list[str | None] = []

        class FakeParserService:
            async def parse_statement(
                self,
                file_content,
                filename,
                bank,
                statement_type,
                password=None,
            ):
                attempts.append(password)
                raise ParseException("Incorrect PDF password.")

        monkeypatch.setattr("app.services.parser_service.ParserService", FakeParserService)
        monkeypatch.setattr(
            "app.services.statement_audit_service.StatementAuditService.record",
            lambda *args, **kwargs: None,
        )

        result = await svc.scan_and_import(
            db=_FakeDbSession(),
            files=[
                {
                    "filepath": str(filepath),
                    "bank": "BOB",
                    "type": "SAVINGS",
                }
            ],
            bank_passwords={"BOB": " wrong-password-one,\nwrong-password-two "},
        )

        assert attempts == ["wrong-password-one", "wrong-password-two"]
        assert result["processed"] == 0
        assert result["failed"] == 1
        assert result["details"][0]["status"] == "failed"
        assert result["details"][0]["error"] == "Incorrect PDF password."
