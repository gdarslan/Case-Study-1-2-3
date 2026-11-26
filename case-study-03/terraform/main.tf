terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
}

  # Uncomment when S3 bucket for state is created
  # backend "s3" {
  #   bucket = "innovatech-terraform-state"
  #   key    = "cs3/terraform.tfstate"
  #   region = "eu-central-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CS3-MA-NCA"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Innovatech"
    }
  }
}
