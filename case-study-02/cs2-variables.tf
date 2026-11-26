variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "ses_sender_email" {
  type        = string
  description = "Verified SES email address to send alerts from"
}

variable "ses_recipient_email" {
  type        = string
  description = "Email address to receive SOAR alerts"
}

variable "soar_api_token_secret_arn" {
  type        = string
  description = "ARN of an existing Secrets Manager secret holding a strong plaintext token; never put the token in Terraform"
}

variable "soar_tls_certificate_arn" {
  type        = string
  description = "ARN of an ACM certificate for the alert listener hostname in the deployment region"
}

variable "alert_source_cidr" {
  type        = string
  description = "Trusted alert producer's IPv4 CIDR"
  validation {
    condition     = can(cidrhost(var.alert_source_cidr, 0)) && var.alert_source_cidr != "0.0.0.0/0"
    error_message = "Supply a restricted CIDR, not unrestricted Internet access."
  }
}
