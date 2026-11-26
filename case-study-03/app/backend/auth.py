"""Demo-only bearer token authentication; no credentials live in source."""
import hmac


def authenticate(header: str | None, admin_token: str, viewer_token: str) -> str | None:
    if min(len(admin_token), len(viewer_token)) < 32 or admin_token == viewer_token:
        return None  # fail closed on missing or ambiguous configuration
    scheme, _, token = (header or "").partition(" ")
    if scheme.lower() != "bearer":
        return None
    if hmac.compare_digest(token.encode(), admin_token.encode()):
        return "admin"
    if hmac.compare_digest(token.encode(), viewer_token.encode()):
        return "viewer"
    return None
