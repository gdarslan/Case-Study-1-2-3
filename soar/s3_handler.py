import boto3
import os
import json
from datetime import datetime, timezone

s3 = boto3.client("s3")


def handler(event, context):
    """
    Receives an alert event and saves it as a JSON file in S3.
    S3_BUCKET is set as an environment variable in Terraform.

    Files are stored with a date-based path, for example:
      soar-event-logs/2026/04/22/20260422T120000Z-HIGH_CPU.json
    """
    bucket = os.environ["S3_BUCKET"]

    now        = datetime.now(timezone.utc)
    alert_type = event.get("alert_type", "UNKNOWN").replace(" ", "_")
    timestamp  = now.strftime("%Y%m%dT%H%M%SZ")

    # Build the S3 key (file path inside the bucket)
    key = f"soar-event-logs/{now.year}/{now.month:02d}/{now.day:02d}/{timestamp}-{alert_type}.json"

    # Upload the alert as a JSON file
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(event),
        ContentType="application/json",
    )

    print(f"Alert saved to s3://{bucket}/{key}")
    return {"status": "ok", "key": key}
