from pathlib import Path

import fitz
import pdfplumber
from pdfminer.pdfdocument import PDFPasswordIncorrect

from app.parsers.base_parser import ParseException
from app.parsing.extraction.artifacts import ExtractedTextDocument


def extract_pdf_text(
    file_path: str | Path,
    *,
    password: str | None = None,
) -> str:
    try:
        doc = fitz.open(str(file_path))
        try:
            if doc.needs_pass:
                if not password:
                    raise ParseException(
                        "PDF is password-protected — please provide the password."
                    )
                authenticated = doc.authenticate(password)
                if not authenticated:
                    raise ParseException("Incorrect PDF password.")
            return "\n".join(page.get_text() for page in doc)
        finally:
            doc.close()
    except ParseException:
        raise
    except Exception:
        pdf_password = password or ""
        try:
            with pdfplumber.open(str(file_path), password=pdf_password) as pdf:
                return "\n".join(page.extract_text() or "" for page in pdf.pages)
        except PDFPasswordIncorrect as exc:
            raise ParseException("Incorrect PDF password.", cause=exc) from exc
        except Exception as exc:
            raise ParseException(f"Failed to extract raw text: {exc}", cause=exc)


def extract_text_document(
    file_path: str | Path,
    *,
    password: str | None = None,
) -> ExtractedTextDocument:
    return ExtractedTextDocument.from_text(
        extract_pdf_text(file_path, password=password)
    )