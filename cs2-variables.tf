variable "ses_sender_email" {
  type        = string
  description = "Verified SES email address to send alerts from"
}

variable "ses_recipient_email" {
  type        = string
  description = "Email address to receive SOAR alerts"
}
