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
    key = "snapr/ford"
    region = "eu-central-1"
    encrypt = true
    profile = "arkleseizure"
  }
}

locals {
  region = "eu-north-1" # stockholm
  username = "arkleseizure"
  deployment = "snapr-mainnet"
  domain = "snapr.net"
  hostname = "ford"
  cname = "ford.snapr.systems"
  admin_email = "ops@snapr.org"
  zone_id = "Z07796421GG5I8U5O58SQ" # snapr.systems
  instance_type = "r5.large" # 3.1 GHz Intel Xeon® Platinum 8000, 2 vcpu, 16g ram
  substrate_release_url = "https://github.com/snapr-org/snapr/releases/download/v3.0.0-alpha-9287555/snapr_v3.0.0-alpha-9287555_amd64"
  substrate_executable = "snapr"
  substrate_chain = "mainnet"
  substrate_name = "ford"
  substrate_port = 30333
  substrate_args = "--validator"
  substrate_rpc_cors = "all"
  substrate_ws_port = 9944
  trusted_cidr_blocks = [
    "185.236.152.0/22", # mp 4404
    "185.189.196.0/22", # mp 4404
  ]
}

module "ford" {
  profile = "arkleseizure"
  username = local.username
  deployment = local.deployment
  hostname = local.hostname
  domain = local.domain
  cname = local.cname
  admin_email = local.admin_email
  zone_id = local.zone_id
  instance_type = local.instance_type
  substrate_release_url = local.substrate_release_url
  substrate_executable = local.substrate_executable
  substrate_chain = local.substrate_chain
  substrate_name = local.substrate_name
  substrate_port = local.substrate_port
  substrate_args = local.substrate_args
  substrate_rpc_cors = local.substrate_rpc_cors
  substrate_ws_port = local.substrate_ws_port
  trusted_cidr_blocks = local.trusted_cidr_blocks
  region = local.region
  source = "../../../module/substrate-node"
  cloud_config_path = "../../../module/substrate-node/cloud-config.yml"
}
