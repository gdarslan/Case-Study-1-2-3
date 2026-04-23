def evaluate(event):
    """
    Decide what actions to take based on alert severity.

    HIGH or CRITICAL  ->  send email  AND  log to S3
    Anything else     ->  only log to S3
    """
    severity = event.get("severity", "").upper()

    if severity in ("HIGH", "CRITICAL"):
        return ["SES", "S3"]

    return ["S3"]
