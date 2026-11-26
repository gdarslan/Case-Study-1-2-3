# Monthly cost budget — REQ-NCA-P3-09, REQ-NCA-P3-13
# Sends email alerts at 80 % ($28) and 100 % ($35) of the monthly limit.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "35"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at 80 % — early warning before the cap is hit
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Alert at 100 % — cap reached
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Forecasted spend alert — warns before the month ends if on track to exceed
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
