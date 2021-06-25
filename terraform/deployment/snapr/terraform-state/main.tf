terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  backend "s3" {
    dynamodb_table = "snapr-terraform-locks"
    bucket = "snapr-terraform-state"
    key = "snapr/terraform-state"
    region = "eu-central-1"
    encrypt = true
    profile = "arkleseizure"
  }
}
provider "aws" {
  profile = "arkleseizure"
  region = "eu-central-1"
}
resource "aws_s3_bucket" "terraform_state" {
  bucket = "snapr-terraform-state"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = {
    Source = "https://github.com/snapr-org/great-green-arkleseizure"
    Owner = "ops@snapr.org"
  }
}
resource "aws_dynamodb_table" "terraform_locks" {
  name = "snapr-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Source = "https://github.com/snapr-org/great-green-arkleseizure"
    Owner = "ops@snapr.org"
  }
}
