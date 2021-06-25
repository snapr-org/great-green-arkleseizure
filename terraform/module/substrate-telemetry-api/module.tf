terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.27"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}
provider "aws" {
  region = var.region
  profile = var.profile
}
data "aws_caller_identity" "current" {}
locals {
  host_keys = yamldecode(data.aws_secretsmanager_secret_version.host_keys.secret_string)
}
resource "aws_secretsmanager_secret" "host_keys" {
  name = "ssh-host-${var.hostname}.${var.domain}"
}
data "aws_secretsmanager_secret_version" "host_keys" {
  secret_id = aws_secretsmanager_secret.host_keys.id
}
data "template_file" "cloud_config" {
  template = file(var.cloud_config_path)
  vars = {
    hostname = var.hostname
    domain = var.domain
    username = var.username
    region = var.region
    cname = var.cname
    admin_email = var.admin_email
    telemetry_release_url = var.telemetry_release_url
    host_key_private = indent(8, local.host_keys.ed25519.private)
    host_key_public = indent(8, local.host_keys.ed25519.public)
    host_key_certificate = indent(8, local.host_keys.ed25519.certificate)
  }
}
data "aws_ami" "ubuntu_latest" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  owners = ["099720109477"] # canonical
}
resource "aws_cloudwatch_log_group" "node" {
  name = "${var.cname}"
  retention_in_days = 30
}
resource "aws_instance" "node" {
  ami = data.aws_ami.ubuntu_latest.id
  instance_type = var.instance_type
  security_groups = [aws_security_group.node.name]
  associate_public_ip_address = true
  root_block_device {
    delete_on_termination = true
    volume_size = 120
  }
  user_data = data.template_file.cloud_config.rendered
  iam_instance_profile = aws_iam_instance_profile.node.name
  tags = {
    Name = var.hostname
    Domain = var.domain
    cname = var.cname
    Source = "https://github.com/snapr-org/great-green-arkleseizure"
    Owner = var.admin_email
  }
}
resource "aws_route53_record" "node" {
  zone_id = var.zone_id
  name = var.cname
  type = "A"
  ttl = var.ttl
  records = [aws_instance.node.public_ip]
}
resource "aws_iam_role" "node" {
  name = "${var.deployment}-${var.hostname}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com",
        }
      }
    ]
  })
}
resource "aws_iam_instance_profile" "node" {
  name = "${var.deployment}-${var.hostname}"
  role = aws_iam_role.node.name
}

resource "aws_iam_role_policy" "node" {
  name = "${var.deployment}-${var.hostname}"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes*",
          "ec2:DescribeTags*",
          "logs:PutLogEvents*",
          "logs:DescribeLogStreams*",
          "logs:DescribeLogGroups*",
          "logs:CreateLogStream*",
          "logs:CreateLogGroup*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ssm:GetParameter",
        ]
        Effect = "Allow"
        Resource = "arn:aws:ssm:*:*:parameter/AmazonCloudWatch-*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:PutObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::manta-network-artifact-${var.region}",
          "arn:aws:s3:::manta-network-artifact-${var.region}/*",
        ]
      },
      {
        Action = [
          "iam:GetServerCertificate",
          "iam:UploadServerCertificate",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:server-certificate/${var.hostname}.${var.domain}",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:server-certificate/${var.cname}",
        ]
      },
      {
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:ssl-${var.hostname}.${var.domain}*",
          "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:ssh-host-${var.hostname}.${var.domain}*",
        ]
      },
    ]
  })
}
resource "aws_security_group" "node" {
  name = "${var.deployment}-${var.hostname}"
}
resource "aws_security_group_rule" "ssh" {
  security_group_id = aws_security_group.node.id
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = var.trusted_cidr_blocks
}
resource "aws_security_group_rule" "http" {
  security_group_id = aws_security_group.node.id
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
}
resource "aws_security_group_rule" "https" {
  security_group_id = aws_security_group.node.id
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
}
resource "aws_security_group_rule" "all_egress" {
  security_group_id = aws_security_group.node.id
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
}
