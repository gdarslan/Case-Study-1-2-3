import json
import logging
import os
import boto3
from flask import Flask, request, jsonify
from botocore.exceptions import BotoCoreError, ClientError
import rule_engine
from security import authorized, normalize_alert

SES_LAMBDA_ARN = os.environ["SES_LAMBDA_ARN"]
S3_LAMBDA_ARN = os.environ["S3_LAMBDA_ARN"]
lambda_client = boto3.client("lambda")
app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 64 * 1024
log = logging.getLogger(__name__)


def invoke_lambda(arn, payload):
    response = lambda_client.invoke(
        FunctionName=arn, InvocationType="Event", Payload=json.dumps(payload).encode()
    )
    if response.get("StatusCode") != 202:
        raise RuntimeError("Lambda invocation was not accepted")


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/alert")
def handle_alert():
    if not authorized(request.headers.get("Authorization", ""), os.getenv("SOAR_API_TOKEN", "")):
        return jsonify({"error": "Unauthorized"}), 401
    try:
        event = normalize_alert(request.get_json(silent=True))
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    actions = rule_engine.evaluate(event)
    accepted = []
    for action, arn in (("SES", SES_LAMBDA_ARN), ("S3", S3_LAMBDA_ARN)):
        if action in actions:
            try:
                invoke_lambda(arn, event)
                accepted.append(action)
            except (BotoCoreError, ClientError, RuntimeError):
                log.exception("Failed to submit %s action", action)
    if len(accepted) != len(actions):
        return jsonify({"status": "partial", "accepted_actions": accepted}), 502
    # Asynchronous submission is not proof the downstream action succeeded.
    return jsonify({"status": "accepted", "actions": accepted}), 202


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
