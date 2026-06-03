from pathlib import Path

import pdfplumber
from pdfminer.pdfdocument import PDFPasswordIncorrect

from app.parsers.base_parser import ParseException
from app.parsing.extraction.artifacts import ExtractedPageTables


def extract_pdf_tables(
    file_path: str | Path,
    *,
    password: str | None = None,
) -> list[ExtractedPageTables]:
    pdf_password = password or ""
    try:
        with pdfplumber.open(str(file_path), password=pdf_password) as pdf:
            return [
                ExtractedPageTables(
                    page_number=index + 1,
                    tables=page.extract_tables() or [],
                )
                for index, page in enumerate(pdf.pages)
            ]
    except PDFPasswordIncorrect as exc:
        raise ParseException("Incorrect PDF password.", cause=exc) from exc
    except Exception as exc:
        raise ParseException(f"Failed to extract table data from PDF: {exc}", cause=exc)