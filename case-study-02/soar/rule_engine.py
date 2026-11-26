def evaluate(event):
    """HIGH/CRITICAL: email and archive. All other severities: archive."""
    if not isinstance(event, dict):
        raise ValueError("Expected an alert object")
    severity = event.get("severity", "")
    if not isinstance(severity, str):
        raise ValueError("Severity must be a string")
    return ["SES", "S3"] if severity.strip().upper() in ("HIGH", "CRITICAL") else ["S3"]
