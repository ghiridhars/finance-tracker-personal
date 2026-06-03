from pathlib import Path

import pytest
from pdfminer.pdfdocument import PDFPasswordIncorrect

from app.parsers.base_parser import ParseException
from app.parsing.extraction.pdf_tables import extract_pdf_tables
from app.parsing.extraction.pdf_text import extract_pdf_text, extract_text_document


class TestPdfTableExtraction:
    def test_extract_pdf_tables_returns_page_artifacts(self, monkeypatch, tmp_path):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        class FakePage:
            def __init__(self, tables):
                self._tables = tables

            def extract_tables(self):
                return self._tables

        class FakePdf:
            def __init__(self, pages):
                self.pages = pages

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

        monkeypatch.setattr(
            "app.parsing.extraction.pdf_tables.pdfplumber.open",
            lambda *args, **kwargs: FakePdf(
                [
                    FakePage([[ ["DATE", "NARRATION"], ["01-01-2024", "Txn"] ]]),
                    FakePage([]),
                ]
            ),
        )

        extracted = extract_pdf_tables(filepath)

        assert len(extracted) == 2
        assert extracted[0].page_number == 1
        assert extracted[0].tables[0][1][1] == "Txn"
        assert extracted[1].tables == []

    def test_extract_pdf_tables_translates_incorrect_password(self, monkeypatch, tmp_path):
        filepath = tmp_path / "protected.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        def raise_incorrect_password(*args, **kwargs):
            raise PDFPasswordIncorrect()

        monkeypatch.setattr(
            "app.parsing.extraction.pdf_tables.pdfplumber.open",
            raise_incorrect_password,
        )

        with pytest.raises(ParseException, match="Incorrect PDF password."):
            extract_pdf_tables(filepath, password="wrong-password")


class TestPdfTextExtraction:
    def test_extract_text_document_builds_split_line_artifact(self, monkeypatch, tmp_path):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        monkeypatch.setattr(
            "app.parsing.extraction.pdf_text.extract_pdf_text",
            lambda *args, **kwargs: " line one \n\nline two ",
        )

        document = extract_text_document(filepath)

        assert document.raw_text == " line one \n\nline two "
        assert document.raw_lines == (" line one ", "", "line two ")
        assert document.stripped_lines == ("line one", "", "line two")

    def test_extract_pdf_text_uses_pdfplumber_fallback(self, monkeypatch, tmp_path):
        filepath = tmp_path / "statement.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        class FakePage:
            def __init__(self, text):
                self._text = text

            def extract_text(self):
                return self._text

        class FakePdf:
            def __init__(self, pages):
                self.pages = pages

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

        monkeypatch.setattr(
            "app.parsing.extraction.pdf_text.fitz.open",
            lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("fitz failed")),
        )
        monkeypatch.setattr(
            "app.parsing.extraction.pdf_text.pdfplumber.open",
            lambda *args, **kwargs: FakePdf([FakePage("hello"), FakePage("world")]),
        )

        text = extract_pdf_text(filepath)

        assert text == "hello\nworld"

    def test_extract_pdf_text_translates_incorrect_password_from_fitz(self, monkeypatch, tmp_path):
        filepath = tmp_path / "protected.pdf"
        filepath.write_bytes(b"%PDF-1.4 test")

        class FakeDoc:
            needs_pass = True

            def authenticate(self, password):
                return False

            def close(self):
                return None

        monkeypatch.setattr(
            "app.parsing.extraction.pdf_text.fitz.open",
            lambda *args, **kwargs: FakeDoc(),
        )

        with pytest.raises(ParseException, match="Incorrect PDF password."):
            extract_pdf_text(filepath, password="wrong-password")