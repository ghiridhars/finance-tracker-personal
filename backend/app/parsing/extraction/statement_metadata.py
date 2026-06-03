import re

from app.parsing.extraction.artifacts import (
    ExtractedStatementMetadata,
    ExtractedTextDocument,
    ensure_text_document,
)


def extract_statement_metadata(
    text: ExtractedTextDocument | str,
) -> ExtractedStatementMetadata:
    document = ensure_text_document(text)
    raw_text = document.raw_text

    period_from: str | None = None
    period_to: str | None = None
    account_number: str | None = None
    card_number: str | None = None

    period = re.search(
        r"(?:from|period[:\s]+)\s*(\d{2}[/-]\d{2}[/-]\d{2,4})\s+to\s+(\d{2}[/-]\d{2}[/-]\d{2,4})",
        raw_text,
        re.IGNORECASE,
    )
    if period:
        period_from = period.group(1)
        period_to = period.group(2)

    acct_patterns = [
        r"account\s*(?:number|no\.?)[:\s]*([\dXx*][\dXx*\s-]{5,}[\dXx*])",
        r"a/c\s*(?:number|no\.?)[:\s]*([\dXx*][\dXx*\s-]{5,}[\dXx*])",
    ]
    for pattern in acct_patterns:
        acct_match = re.search(pattern, raw_text, re.IGNORECASE)
        if acct_match:
            account_number = acct_match.group(1).strip()
            break

    card_patterns = [
        r"card\s*(?:number|no\.?)[:\s]*([\dXx*]{4}[\s-]?[\dXx*]{4}[\s-]?[\dXx*]{4}[\s-]?[\dXx*]{4})",
        r"(\d{4,6}[Xx*]{4,6}\d{4})",
    ]
    for pattern in card_patterns:
        card_match = re.search(pattern, raw_text, re.IGNORECASE)
        if card_match:
            card_number = card_match.group(1).strip()
            break

    return ExtractedStatementMetadata(
        period_from=period_from,
        period_to=period_to,
        account_number=account_number,
        card_number=card_number,
    )