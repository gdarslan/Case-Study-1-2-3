variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "innovatech"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "innovatech"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "innovatech_admin"
}

variable "db_password" {
  description = "PostgreSQL master password — set via TF_VAR_db_password environment variable"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "budget_alert_email" {
  description = "Email address that receives cost budget alerts"
  type        = string
}
