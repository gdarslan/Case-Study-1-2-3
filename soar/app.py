import json
import os
import boto3
from flask import Flask, request, jsonify
import rule_engine

SES_LAMBDA_ARN = os.environ["SES_LAMBDA_ARN"]
S3_LAMBDA_ARN  = os.environ["S3_LAMBDA_ARN"]

lambda_client = boto3.client("lambda")
app = Flask(__name__)


def invoke_lambda(arn, payload):
    lambda_client.invoke(
        FunctionName=arn,
        InvocationType="Event",
        Payload=json.dumps(payload).encode(),
    )


@app.route("/alert", methods=["POST"])
def handle_alert():
    event = request.get_json(force=True) or {}

    alert_type = event.get("alert_type", "UNKNOWN")
    severity   = event.get("severity",   "UNKNOWN")
    print(f"Received alert: {alert_type} / {severity}")

    actions = rule_engine.evaluate(event)
    print(f"Actions to take: {actions}")

    if "SES" in actions:
        print("-> Sending email alert")
        invoke_lambda(SES_LAMBDA_ARN, event)

    if "S3" in actions:
        print("-> Logging alert to S3")
        invoke_lambda(S3_LAMBDA_ARN, event)

    print(f"SOAR_METRIC | Action: {actions} | Severity: {severity} | Status: SUCCESS")
    return jsonify({"status": "ok", "actions": actions})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)