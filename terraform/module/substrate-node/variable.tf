variable "deployment" {
  type = string
}
variable "hostname" {
  type = string
}
variable "domain" {
  type = string
}
variable "cname" {
  type = string
}
variable "zone_id" {
  type = string
}
variable "ttl" {
  type = string
  default = "60"
}
variable "region" {
  type = string
}
variable "profile" {
  type = string
}
variable "username" {
  type = string
}
variable "admin_email" {
  type = string
}
variable "instance_type" {
  # https://calculator.aws/#/createCalculator/EC2

  # r: memory optimised
  # - r5a: 2.5 GHz AMD EPYC 7000
  #   - r5a.large: 2 vcpu, 16g ram, 120g ssd, $0.113 hourly, $63.83 monthly (us ohio)
  #   - r5a.xlarge: 4 vcpu, 32g ram, 120g ssd, $0.226 hourly, $115.66 monthly (us ohio)
  #   - r5a.2xlarge: 4 vcpu, 64g ram, 120g ssd, $0.452 hourly, $220.05 monthly (us ohio)
  # - r5: 3.1 GHz Intel Xeon® Platinum 8000
  #   - r5.large: 2 vcpu, 16g ram, 120g ssd, $0.126 hourly, $69.67 monthly (eu stockholm)
  #   - r5.xlarge: 4 vcpu, 32g ram, 120g ssd, $0.252 hourly, $128.07 monthly (eu stockholm)
  #   - r5.2xlarge: 4 vcpu, 64g ram, 120g ssd, $0.504 hourly, $244.14 monthly (us ohio)

  type = string
  default = "r5.large"
}
variable "cloud_config_path" {
  type = string
}
variable "trusted_cidr_blocks" {
  type = list(string)
}
variable "substrate_executable" {
  type = string
}
variable "substrate_chain" {
  type = string
}
variable "substrate_name" {
  type = string
}
variable "substrate_port" {
  type = number
  default = 30333
}
variable "substrate_args" {
  type = string
}
variable "substrate_rpc_cors" {
  type = string
  default = "all"
}
variable "substrate_ws_port" {
  type = number
  default = 9944
}
variable "substrate_release_url" {
  type = string
}