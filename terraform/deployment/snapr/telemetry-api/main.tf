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
    key = "snapr/telemetry/api"
    region = "eu-central-1"
    encrypt = true
    profile = "arkleseizure"
  }
}

locals {
  username = "arkleseizure"
  deployment = "snapr"
  domain = "snapr.org"
  hostname = "telemetry"
  cname = "telemetry.snapr.systems"
  admin_email = "ops@snapr.org"
  zone_id = "Z07796421GG5I8U5O58SQ" # snapr.systems
  telemetry_release_url = "https://github.com/snapr-org/snapr-telemetry/releases/download/v0.3.0-f3cca13/telemetry"
  trusted_cidr_blocks = [
    "185.236.154.48/32", # mp 4404
  ]
}

module "snapr-telemetry-api" {
  profile = "arkleseizure"
  username = local.username
  deployment = local.deployment
  hostname = local.hostname
  domain = local.domain
  cname = local.cname
  admin_email = local.admin_email
  zone_id = local.zone_id
  telemetry_release_url = local.telemetry_release_url
  trusted_cidr_blocks = local.trusted_cidr_blocks
  region = "eu-central-1"
  source = "../../../module/substrate-telemetry-api"
  cloud_config_path = "../../../module/substrate-telemetry-api/cloud-config.yml"
}