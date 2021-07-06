provider "aws" {
  region = var.region
  profile = var.profile
}

locals {
  host_keys = yamldecode(data.aws_secretsmanager_secret_version.host_keys.secret_string)
  shared = yamldecode(data.aws_secretsmanager_secret_version.shared.secret_string)
}

data "aws_caller_identity" "current" {}
resource "aws_secretsmanager_secret" "host_keys" {
  name = "ssh-host-${var.cname}"
}
data "aws_secretsmanager_secret_version" "host_keys" {
  secret_id = aws_secretsmanager_secret.host_keys.id
}
resource "aws_secretsmanager_secret" "shared" {
  name = "shared-${var.cname}"
}
data "aws_secretsmanager_secret_version" "shared" {
  secret_id = aws_secretsmanager_secret.shared.id
}
data "template_file" "cloud_config" {
  template = file(var.cloud_config_path)
  vars = {
    deployment = var.deployment
    hostname = var.hostname
    domain = var.domain
    username = var.username
    region = var.region
    cname = var.cname
    admin_email = var.admin_email

    host_key_private = indent(8, local.host_keys.ed25519.private)
    host_key_public = indent(8, local.host_keys.ed25519.public)
    host_key_certificate = indent(8, local.host_keys.ed25519.certificate)

    substrate_release_url = var.substrate_release_url
    substrate_executable = var.substrate_executable
    substrate_chain = var.substrate_chain
    substrate_name = var.substrate_name
    substrate_port = var.substrate_port
    substrate_args = var.substrate_args
    substrate_rpc_cors = var.substrate_rpc_cors
    substrate_ws_port = var.substrate_ws_port

    smtp_username = local.shared.smtp.username
    smtp_password = local.shared.smtp.password
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
  description = "parachain node role"
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
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.node.arn,
        ]
      },
      {
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.node.arn,
          "${aws_s3_bucket.node.arn}/*",
        ]
      },
      {
        Action = [
          "iam:GetServerCertificate",
          "iam:DeleteServerCertificate",
          "iam:UploadServerCertificate",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:server-certificate/${var.cname}",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:server-certificate/${var.hostname}.${var.domain}",
        ]
      },
      {
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:ssl-${var.hostname}.${var.domain}*",
          "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:ssh-host-${var.cname}*",
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
resource "aws_security_group_rule" "p2p" {
  security_group_id = aws_security_group.node.id
  type = "ingress"
  from_port = var.substrate_port
  to_port = var.substrate_port
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


# todo: add grafana ingress. eg:
#  ingress {
#    from_port = 30333
#    to_port = 30333
#    protocol = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#    ipv6_cidr_blocks = ["::/0"]
#  }
#  ingress {
#    from_port = 9090
#    to_port = 9090
#    protocol = "tcp"
#    cidr_blocks = ["${var.metric_ip}/32"]
#  }
#  ingress {
#    from_port = 9093
#    to_port = 9093
#    protocol = "tcp"
#    cidr_blocks = ["${var.metric_ip}/32"]
#  }

resource "aws_ses_domain_identity" "node" {
  domain = aws_route53_record.node.name
}
resource "aws_ses_email_identity" "node_default_user" {
  email = "${var.username}@${aws_ses_domain_identity.node.domain}"
}
resource "aws_ses_domain_mail_from" "node" {
  domain = aws_ses_domain_identity.node.domain
  mail_from_domain = "bounce.${aws_ses_domain_identity.node.domain}"
}
resource "aws_route53_record" "node_mx" {
  zone_id = aws_route53_record.node.zone_id
  name = aws_ses_domain_mail_from.node.mail_from_domain
  type = "MX"
  ttl = "600"
  records = [
    "10 feedback-smtp.us-west-2.amazonses.com"
  ]
}
resource "aws_route53_record" "node_txt_spf" {
  zone_id = aws_route53_record.node.zone_id
  name = aws_ses_domain_mail_from.node.mail_from_domain
  type = "TXT"
  ttl = "600"
  records = [
    "v=spf1 include:amazonses.com -all"
  ]
}
resource "aws_route53_record" "node_txt_ses" {
  zone_id = aws_route53_record.node.zone_id
  name = "_amazonses.${aws_ses_domain_identity.node.id}"
  type = "TXT"
  ttl = "600"
  records = [
    aws_ses_domain_identity.node.verification_token
  ]
}
resource "aws_ses_domain_identity_verification" "node" {
  domain = aws_ses_domain_identity.node.id
  depends_on = [
    aws_route53_record.node_txt_ses
  ]
}
resource "aws_s3_bucket" "node" {
  bucket = "${var.deployment}-${var.region}-${var.hostname}"
  acl = "private"
  versioning {
    enabled = false
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
