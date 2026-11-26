variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "casestudy1"
}

variable "db_name" {
  type    = string
  default = "casedb"
}

variable "db_username" {
  type    = string
  default = "deniz"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 SSH key pair in the target AWS region"
  type        = string
}

variable "admin_cidr" {
  description = "Trusted administrator IPv4 CIDR for SSH and monitoring"
  type        = string
  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "Use a restricted administrative CIDR."
  }
}
