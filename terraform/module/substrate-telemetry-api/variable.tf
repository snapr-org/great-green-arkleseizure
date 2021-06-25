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
  type = string
  default = "t3.micro"
}
variable "cloud_config_path" {
  type = string
}
variable "telemetry_release_url" {
  type = string
}
variable "trusted_cidr_blocks" {
  type    = list(string)
}
