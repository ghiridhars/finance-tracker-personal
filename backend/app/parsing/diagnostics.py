from collections.abc import Mapping
from typing import Any

from app.parsing.errors import (
    ERROR_GENERIC_PARSE,
    ERROR_LLM_FALLBACK,
    STAGE_GENERIC_PARSE,
    STAGE_LLM_FALLBACK,
)


def extract_parse_failure(result: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(result, Mapping):
        return None

    trace = result.get("trace")
    failure = trace.get("failure") if isinstance(trace, Mapping) else None

    payload: dict[str, Any] = {}
    if isinstance(failure, Mapping):
        if failure.get("stage") is not None:
            payload["stage"] = failure.get("stage")
        if failure.get("code") is not None:
            payload["code"] = failure.get("code")
        if failure.get("owner") is not None:
            payload["owner"] = failure.get("owner")
        if failure.get("message") is not None:
            payload["message"] = failure.get("message")

    if not payload:
        if result.get("llm_status") == "attempted":
            payload["stage"] = STAGE_LLM_FALLBACK
            payload["code"] = ERROR_LLM_FALLBACK
        elif result.get("generic_error"):
            payload["stage"] = STAGE_GENERIC_PARSE
            payload["code"] = ERROR_GENERIC_PARSE

    if not payload:
        return None

    if "message" not in payload and result.get("error") is not None:
        payload["message"] = result.get("error")
    if result.get("parser") is not None:
        payload["parser"] = result.get("parser")
    if result.get("generic_error") is not None:
        payload["generic_error"] = result.get("generic_error")
    if result.get("llm_status") not in (None, "not_attempted"):
        payload["llm_status"] = result.get("llm_status")
    if result.get("llm_error") is not None:
        payload["llm_error"] = result.get("llm_error")

    return payload


def annotate_parse_failure_message(
    message: str,
    parse_failure: Mapping[str, Any] | None,
) -> str:
    if not message or not isinstance(parse_failure, Mapping):
        return message

    parts: list[str] = []
    if parse_failure.get("stage"):
        parts.append(f"stage: {parse_failure['stage']}")
    if parse_failure.get("code"):
        parts.append(f"code: {parse_failure['code']}")

    if not parts:
        return message

    suffix = f" ({', '.join(parts)})"
    if message.endswith(suffix):
        return message
    return f"{message}{suffix}"