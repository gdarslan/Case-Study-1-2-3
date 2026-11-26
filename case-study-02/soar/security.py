"""Input validation and fail-closed authentication for the alert receiver."""
import hmac

ALERT_FIELDS = ("alert_type", "severity", "source_ip", "hostname", "timestamp", "message")


def authorized(header: str, expected: str) -> bool:
    if not isinstance(expected, str) or len(expected) < 32:
        return False
    scheme, _, value = (header or "").partition(" ")
    return scheme.lower() == "bearer" and hmac.compare_digest(value.encode(), expected.encode())


def normalize_alert(event):
    if not isinstance(event, dict):
        raise ValueError("Expected a JSON object")
    result = dict(event)
    for field in ALERT_FIELDS:
        if field in result and (not isinstance(result[field], str) or len(result[field]) > 4096):
            raise ValueError(f"{field} must be a string of at most 4096 characters")
    result["severity"] = result.get("severity", "UNKNOWN").strip().upper() or "UNKNOWN"
    return result
