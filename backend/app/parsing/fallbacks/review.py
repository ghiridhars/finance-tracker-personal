from dataclasses import asdict, dataclass


@dataclass(frozen=True, slots=True)
class ReviewFallbackOutcome:
    type: str
    action: str
    confidence: str
    reason_codes: tuple[str, ...]
    message: str

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["reason_codes"] = list(self.reason_codes)
        return payload


def build_review_fallback(validation) -> ReviewFallbackOutcome | None:
    if validation.trusted:
        return None

    summary = validation.summary()
    reason_codes = tuple(summary["failed_codes"])
    codes_text = ", ".join(reason_codes) if reason_codes else "unknown validation issues"

    return ReviewFallbackOutcome(
        type="review",
        action="manual_review",
        confidence=summary["confidence"],
        reason_codes=reason_codes,
        message=f"Manual review required: {codes_text}",
    )