data "aws_caller_identity" "current" {}

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = var.networking_state_key
    region = var.aws_region
  }
}

data "aws_vpc" "this" {
  id = data.terraform_remote_state.networking.outputs.vpc_id
}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  vpc_id         = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_id      = data.terraform_remote_state.networking.outputs.public_subnet_ids[0]
  ec2_key_name   = var.generate_ssh_key_pair ? aws_key_pair.generated[0].key_name : (var.ec2_key_name != "" ? var.ec2_key_name : null)
}

module "config_bucket" {
  source = "../../../../modules/s3-private"

  name          = "${var.name}-config"
  bucket_name   = "${var.name}-config-${local.aws_account_id}"
  force_destroy = true
}

module "ec2_ssm" {
  source = "../../../../modules/ec2-instance-profile-ssm"
  name   = "${var.name}-ec2"
}

data "aws_iam_policy_document" "s3_config" {
  statement {
    sid = "ReadConfigBucket"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      module.config_bucket.bucket_arn,
      "${module.config_bucket.bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_config" {
  name   = "${var.name}-s3-config"
  role   = module.ec2_ssm.iam_role_name
  policy = data.aws_iam_policy_document.s3_config.json
}

resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/ec2/${var.name}/system"
  retention_in_days = var.cloudwatch_log_retention_days
}

data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid = "PublishToInstanceLogGroup"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.ec2.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "${var.name}-cloudwatch-logs"
  role   = module.ec2_ssm.iam_role_name
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}

locals {
  cw_agent_json = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/messages"
              log_group_name  = aws_cloudwatch_log_group.ec2.name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/cloud-init-output.log"
              log_group_name  = aws_cloudwatch_log_group.ec2.name
              log_stream_name = "{instance_id}-cloud-init"
            }
          ]
        }
      }
    }
  })
}

# Public edge: attached only to the Nginx EC2 (HTTP/S, optional SSH).
resource "aws_security_group" "edge" {
  name        = "${var.name}-edge"
  description = "Ingress for external callers to Nginx on this MVP stack."
  vpc_id      = local.vpc_id

  egress {
    description = "all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "edge" {
  for_each = {
    for pair in setproduct(var.edge_ingress_ports, var.edge_ingress_cidrs) :
    "${pair[0]}-${replace(pair[1], "/", "_")}" => {
      port = pair[0]
      cidr = pair[1]
    }
  }

  security_group_id = aws_security_group.edge.id
  description       = "HTTP_S_from_configured-CIDRs"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.edge.id
  description       = "SSH_from_configured-CIDRs"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# LiteLLM + Postgres: only this SG on the app instance; not reachable from the public Internet.
resource "aws_security_group" "litellm" {
  name        = "${var.name}-litellm-internal"
  description = "LiteLLM port from VPC and from Nginx edge host only."
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "litellm_from_vpc" {
  security_group_id = aws_security_group.litellm.id
  description       = "LiteLLM_from_VPC_CIDR"
  from_port         = var.litellm_port
  to_port           = var.litellm_port
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.this.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "litellm_from_nginx_edge_sg" {
  security_group_id            = aws_security_group.litellm.id
  description                  = "LiteLLM_from_Nginx_EC2_edge_SG"
  from_port                    = var.litellm_port
  to_port                      = var.litellm_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.edge.id
}

data "aws_ssm_parameter" "al2023_x86" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

module "litellm_ec2" {
  source = "../../../../modules/ec2-instance"

  ami                         = data.aws_ssm_parameter.al2023_x86.value
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.litellm.id]
  iam_instance_profile        = module.ec2_ssm.instance_profile_name
  associate_public_ip_address = true
  key_name                    = local.ec2_key_name
  root_volume_size_gb         = var.volume_size_gb
  instance_name               = "${var.name}-litellm"

  user_data = templatefile("${path.module}/user-data-litellm.sh.tpl", {
    cw_agent_b64              = base64encode(local.cw_agent_json)
    bootstrap_bucket          = module.config_bucket.bucket_id
    aws_region                = var.aws_region
    extra_user_data           = var.user_data
    use_git_clone             = var.use_git_clone
    git_repo_ssh_url          = var.git_repo_ssh_url
    git_branch                = var.git_branch
    git_clone_path            = var.git_clone_path
    git_compose_relative_path = var.git_compose_relative_path
    github_deploy_ssm_name    = var.use_git_clone ? aws_ssm_parameter.github_deploy_private_key[0].name : ""
  })

  tags = {
    Role = "litellm"
  }

  depends_on = [
    aws_s3_object.litellm_compose,
    aws_s3_object.litellm_config_yaml,
  ]
}

module "nginx_ec2" {
  source = "../../../../modules/ec2-instance"

  ami                         = data.aws_ssm_parameter.al2023_x86.value
  instance_type               = var.nginx_instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.edge.id]
  iam_instance_profile        = module.ec2_ssm.instance_profile_name
  associate_public_ip_address = true
  key_name                    = local.ec2_key_name
  root_volume_size_gb         = var.nginx_volume_size_gb
  instance_name               = "${var.name}-nginx-edge"

  user_data = templatefile("${path.module}/user-data-nginx.sh.tpl", {
    cw_agent_b64     = base64encode(local.cw_agent_json)
    bootstrap_bucket = module.config_bucket.bucket_id
    aws_region       = var.aws_region
  })

  tags = {
    Role = "nginx-edge"
  }

  depends_on = [
    module.litellm_ec2,
    aws_s3_object.nginx_edge,
  ]
}
