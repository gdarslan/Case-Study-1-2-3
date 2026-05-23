terraform {
  backend "s3" {
    bucket         = "tfstate-gorkem-cs1-271443695716-euc1"
    key            = "terraform123/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
