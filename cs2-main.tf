data "aws_caller_identity" "current" {}

# S3 BUCKET  (alert log storage)
#

resource "aws_s3_bucket" "soar_logs" {
  bucket        = "soar-event-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "soar-event-logs" }
}


# IAM ROLE  

resource "aws_iam_role" "lambda_role" {
  name = "soar-lambda-role"

  # Trust policy: allows Lambda to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "soar-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Send emails via SES
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        # Write files to the soar-logs S3 bucket
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.soar_logs.arn}/*"
      },
      {
        # Invoke other Lambda functions
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "*"
      },
      {
        # Write logs to CloudWatch (needed for print() output)
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# LAMBDA: SOAR HANDLER  (main entry point)
#

# Package app.py and rule_engine.py into a zip file for deployment
data "archive_file" "soar_handler" {
  type        = "zip"
  output_path = "${path.module}/soar/soar_handler.zip"

  source {
    content  = file("${path.module}/soar/app.py")
    filename = "app.py"
  }
  source {
    content  = file("${path.module}/soar/rule_engine.py")
    filename = "rule_engine.py"
  }
}

resource "aws_lambda_function" "soar_handler" {
  function_name    = "soar-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.handler"       # file.function_name
  runtime          = "python3.12"
  filename         = data.archive_file.soar_handler.output_path
  source_code_hash = data.archive_file.soar_handler.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SES_LAMBDA_ARN = aws_lambda_function.ses_alert.arn
      S3_LAMBDA_ARN  = aws_lambda_function.s3_log.arn
    }
  }
}


# LAMBDA: SES ALERT
# Sends an HTML email when called with an alert payload.


data "archive_file" "ses_lambda" {
  type        = "zip"
  source_file = "${path.module}/soar/ses_handler.py"
  output_path = "${path.module}/soar/ses_handler.zip"
}

resource "aws_lambda_function" "ses_alert" {
  function_name    = "soar-ses-alert"
  role             = aws_iam_role.lambda_role.arn
  handler          = "ses_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ses_lambda.output_path
  source_code_hash = data.archive_file.ses_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      SENDER_EMAIL    = var.ses_sender_email
      RECIPIENT_EMAIL = var.ses_recipient_email
    }
  }
}

# LAMBDA: S3 LOG
# Saves the alert as a JSON file in the S3 bucket.


data "archive_file" "s3_lambda" {
  type        = "zip"
  source_file = "${path.module}/soar/s3_handler.py"
  output_path = "${path.module}/soar/s3_handler.zip"
}

resource "aws_lambda_function" "s3_log" {
  function_name    = "soar-s3-log"
  role             = aws_iam_role.lambda_role.arn
  handler          = "s3_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.s3_lambda.output_path
  source_code_hash = data.archive_file.s3_lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.soar_logs.bucket
    }
  }
}

# ─────────────────────────────────────────
# API GATEWAY  (HTTP trigger)
# Creates a public HTTPS endpoint.
# Send a POST request to /alert with an alert JSON body
# and the soar_handler Lambda will process it.
#
# Example:
#   curl -X POST https://<url>/alert \
#        -H "Content-Type: application/json" \
#        -d '{"alert_type":"SSH_BRUTE_FORCE","severity":"HIGH","source_ip":"1.2.3.4"}'
# ─────────────────────────────────────────

resource "aws_apigatewayv2_api" "soar_api" {
  name          = "soar-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "soar_integration" {
  api_id             = aws_apigatewayv2_api.soar_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.soar_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "soar_route" {
  api_id    = aws_apigatewayv2_api.soar_api.id
  route_key = "POST /alert"
  target    = "integrations/${aws_apigatewayv2_integration.soar_integration.id}"
}

resource "aws_apigatewayv2_stage" "soar_stage" {
  api_id      = aws_apigatewayv2_api.soar_api.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to call the soar_handler Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.soar_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.soar_api.execution_arn}/*/*"
}

# ─────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────

output "soar_api_url" {
  description = "POST an alert JSON to this endpoint to trigger SOAR"
  value       = "${aws_apigatewayv2_api.soar_api.api_endpoint}/alert"
}

output "s3_bucket_name" {
  description = "Alert logs are stored in this S3 bucket"
  value       = aws_s3_bucket.soar_logs.bucket
}
