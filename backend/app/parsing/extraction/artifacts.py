from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ExtractedPageTables:
    page_number: int
    tables: list[list[list[str | None]]]


@dataclass(frozen=True, slots=True)
class ExtractedTextDocument:
    raw_text: str
    raw_lines: tuple[str, ...]
    stripped_lines: tuple[str, ...]

    @classmethod
    def from_text(cls, raw_text: str) -> "ExtractedTextDocument":
        raw_lines = tuple(raw_text.split("\n"))
        return cls(
            raw_text=raw_text,
            raw_lines=raw_lines,
            stripped_lines=tuple(line.strip() for line in raw_lines),
        )


@dataclass(frozen=True, slots=True)
class ExtractedStatementMetadata:
    period_from: str | None = None
    period_to: str | None = None
    account_number: str | None = None
    card_number: str | None = None

    def to_dict(self) -> dict[str, str]:
        payload: dict[str, str] = {}
        if self.period_from is not None:
            payload["period_from"] = self.period_from
        if self.period_to is not None:
            payload["period_to"] = self.period_to
        if self.account_number is not None:
            payload["account_number"] = self.account_number
        if self.card_number is not None:
            payload["card_number"] = self.card_number
        return payload


def ensure_text_document(
    value: ExtractedTextDocument | str,
) -> ExtractedTextDocument:
    if isinstance(value, ExtractedTextDocument):
        return value
    return ExtractedTextDocument.from_text(value)