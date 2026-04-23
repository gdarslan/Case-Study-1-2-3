import json
import os
import boto3
import rule_engine

# Lambda ARNs are passed in as environment variables (set in Terraform)
SES_LAMBDA_ARN = os.environ["SES_LAMBDA_ARN"]
S3_LAMBDA_ARN  = os.environ["S3_LAMBDA_ARN"]

lambda_client = boto3.client("lambda")


def invoke_lambda(arn, payload):
    """Call another Lambda function and pass the alert as payload."""
    lambda_client.invoke(
        FunctionName=arn,
        InvocationType="Event",          # async: don't wait for the result
        Payload=json.dumps(payload).encode(),
    )


def handler(event, context):
    """
    Main SOAR entry point.
    API Gateway calls this function when an alert comes in.
    It reads the alert, decides what to do, and calls the right Lambda(s).
    """
    alert_type = event.get("alert_type", "UNKNOWN")
    severity   = event.get("severity",   "UNKNOWN")
    print(f"Received alert: {alert_type} / {severity}")

    # rule_engine looks at the severity and returns a list of actions
    actions = rule_engine.evaluate(event)
    print(f"Actions to take: {actions}")

    if "SES" in actions:
        print("-> Sending email alert")
        invoke_lambda(SES_LAMBDA_ARN, event)

    if "S3" in actions:
        print("-> Logging alert to S3")
        invoke_lambda(S3_LAMBDA_ARN, event)

    return {"status": "ok", "actions": actions}
print(f"SOAR_METRIC | Action: {actions} | Severity: {severity} | Status: SUCCESS")