import boto3
import os
import json

ses = boto3.client("ses")


def handler(event, context):
    """
    Receives an alert event and sends an HTML email via AWS SES.
    SENDER_EMAIL and RECIPIENT_EMAIL are set as environment variables in Terraform.
    """
    sender    = os.environ["SENDER_EMAIL"]
    recipient = os.environ["RECIPIENT_EMAIL"]

    # Read alert fields from the event (use defaults if a field is missing)
    alert_type = event.get("alert_type", "UNKNOWN")
    severity   = event.get("severity",   "UNKNOWN")
    source_ip  = event.get("source_ip",  "N/A")
    hostname   = event.get("hostname",   "N/A")
    timestamp  = event.get("timestamp",  "N/A")
    message    = event.get("message",    "No details provided")

    # Build a simple HTML email body
    body = f"""
    <h2>Security Alert - {severity}</h2>
    <table>
      <tr><td><b>Type</b></td>      <td>{alert_type}</td></tr>
      <tr><td><b>Severity</b></td>  <td>{severity}</td></tr>
      <tr><td><b>Source IP</b></td> <td>{source_ip}</td></tr>
      <tr><td><b>Hostname</b></td>  <td>{hostname}</td></tr>
      <tr><td><b>Time</b></td>      <td>{timestamp}</td></tr>
      <tr><td><b>Message</b></td>   <td>{message}</td></tr>
    </table>
    """

    ses.send_email(
        Source=sender,
        Destination={"ToAddresses": [recipient]},
        Message={
            "Subject": {"Data": f"[SOAR] {severity} alert: {alert_type}"},
            "Body":    {"Html": {"Data": body}},
        },
    )

    print(f"Email sent: {alert_type} / {severity}")
    return {"status": "ok"}
