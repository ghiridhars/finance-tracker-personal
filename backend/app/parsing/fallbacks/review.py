from dataclasses import asdict, dataclass


@dataclass(frozen=True, slots=True)
class ReviewFallbackOutcome:
    type: str
    action: str
    confidence: str
    reason_codes: tuple[str, ...]
    message: str
    mismatched_indices: tuple[int, ...] = ()
    valid_indices: tuple[int, ...] = ()

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["reason_codes"] = list(self.reason_codes)
        payload["mismatched_indices"] = list(self.mismatched_indices)
        payload["valid_indices"] = list(self.valid_indices)
        return payload


def build_review_fallback(validation) -> ReviewFallbackOutcome | None:
    if validation.trusted:
        return None

    summary = validation.summary()
    reason_codes = tuple(summary["failed_codes"])
    codes_text = ", ".join(reason_codes) if reason_codes else "unknown validation issues"

    mismatched = tuple(getattr(validation, "mismatched_indices", []) or [])
    valid = tuple(getattr(validation, "valid_indices", []) or [])

    return ReviewFallbackOutcome(
        type="review",
        action="manual_review",
        confidence=summary["confidence"],
        reason_codes=reason_codes,
        message=f"Manual review required: {codes_text}",
        mismatched_indices=mismatched,
        valid_indices=valid,
    )