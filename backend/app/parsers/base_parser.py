"""
Base PDF statement parser using pdfplumber.
Replaces: PdfBoxStatementParser.java (abstract class using Apache PDFBox)

Migration notes:
  - PDFBox → pdfplumber (pure Python, better table extraction)
  - PDFTextStripper.setSortByPosition(true) → pdfplumber extracts in reading order by default
  - PDFTextStripper.setSpacingTolerance(0.5f) → pdfplumber handles spacing internally
  - Custom error-resilient processTextPosition/writeString → pdfplumber is inherently more error-tolerant
  - PDFTextStripperByArea (area-based parsing) → pdfplumber's page.crop() / page.within_bbox()
"""
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pdfplumber

logger = logging.getLogger(__name__)


class ParseException(Exception):
    """Replaces: app.personal.parser.ParseException (Java checked exception)"""

    def __init__(self, message: str, cause: Exception | None = None):
        super().__init__(message)
        self.cause = cause


@dataclass
class ParseResult:
    """
    Replaces: app.personal.parser.ParseResult
    FIX: Uses generic typing instead of raw Object (Java version used Object with casts).
    """
    success: bool
    result: Any | None = None
    error_message: str | None = None

    @staticmethod
    def ok(result: Any) -> "ParseResult":
        return ParseResult(success=True, result=result)

    @staticmethod
    def failure(error_message: str) -> "ParseResult":
        return ParseResult(success=False, error_message=error_message)


@dataclass
class ParserProfile:
    """
    Replaces: app.personal.parser.ParserProfile
    Map of region name -> [x, y, width, height] for area-based PDF extraction.
    """
    regions: dict[str, list[float]] | None = None


class BaseStatementParser(ABC):
    """
    Abstract base class for bank statement PDF parsers.
    Replaces: PdfBoxStatementParser.java

    Uses pdfplumber instead of PDFBox for PDF text extraction.
    pdfplumber advantages:
      - Pure Python (no Java dependency)
      - Better handling of tabular data
      - Built-in table detection
      - More consistent text extraction
    """

    def parse(self, file_path: str | Path) -> ParseResult:
        """
        Parse a PDF file and return structured data.
        Replaces: PdfBoxStatementParser.parse(File)
        """
        file_path = Path(file_path)
        if not file_path.exists():
            raise ParseException(f"File not found: {file_path}")

        try:
            text = self._extract_text(file_path)

            logger.info(f"Extracted text from PDF ({len(text)} chars)")
            logger.debug(f"PDF text preview (first 200 chars):\n{text[:200]}")

            return self.parse_text(text)

        except ParseException:
            raise
        except Exception as e:
            raise ParseException(f"Failed to read PDF: {e}", cause=e)

    def extract_raw_text(self, file_path: str | Path) -> str:
        """
        Extract raw text from PDF.
        Replaces: PdfBoxStatementParser.extractRawText(File)
        """
        return self._extract_text(Path(file_path))

    def parse_by_area(self, file_path: str | Path, profile: ParserProfile) -> ParseResult:
        """
        Area-based PDF parsing using region coordinates.
        Replaces: PdfBoxStatementParser.parseByArea(File, ParserProfile)
        """
        if profile is None or not profile.regions:
            return self.parse(file_path)

        file_path = Path(file_path)
        try:
            with pdfplumber.open(str(file_path)) as pdf:
                if not pdf.pages:
                    raise ParseException("PDF has no pages")

                page = pdf.pages[0]
                parts: list[str] = []

                for name, coords in profile.regions.items():
                    x, y, w, h = coords
                    # pdfplumber uses (x0, top, x1, bottom) bounding box
                    bbox = (x, y, x + w, y + h)
                    cropped = page.crop(bbox)
                    region_text = cropped.extract_text() or ""
                    parts.append(region_text)

                combined_text = "\n---\n".join(parts)
                return self.parse_text(combined_text)

        except ParseException:
            raise
        except Exception as e:
            raise ParseException(f"Failed to read PDF by area: {e}", cause=e)

    @abstractmethod
    def parse_text(self, text: str) -> ParseResult:
        """
        Parse extracted text into structured data.
        Subclasses implement bank-specific parsing logic.
        Replaces: abstract parseText(String) in PdfBoxStatementParser
        """
        ...

    def _extract_text(self, file_path: Path) -> str:
        """
        Extract all text from a PDF using pdfplumber.
        Replaces the custom PDFTextStripper with error-resilient overrides.

        pdfplumber handles text extraction more cleanly than PDFBox:
        - No need for custom processTextPosition/writeString overrides
        - Built-in sort by position
        - Better spacing detection
        """
        try:
            with pdfplumber.open(str(file_path)) as pdf:
                logger.info(f"PDF has {len(pdf.pages)} pages")

                all_text: list[str] = []
                for i, page in enumerate(pdf.pages):
                    try:
                        page_text = page.extract_text() or ""
                        all_text.append(page_text)
                    except Exception as e:
                        logger.warning(f"Failed to extract text from page {i + 1}: {e}")

                return "\n".join(all_text)

        except Exception as e:
            raise ParseException(f"Failed to extract raw text: {e}", cause=e)
